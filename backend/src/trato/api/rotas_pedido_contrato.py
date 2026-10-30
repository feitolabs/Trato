"""Rotas que o app usa em torno do orçamento e do contrato: detalhe do orçamento, cobrança e
estado do pagamento, garantia, aditivos, nota de material, avaliação, perfil e pedidos abertos.

`{contrato_id}` nas rotas é o **id do pedido**: o contrato é um por pedido e não tem outro id.
Nenhuma regra de dinheiro mora aqui: a taxa vem do `ProvedorTaxa`, a cobrança do
`ServicoPagamento` e o app só pede e mostra. "Pago" só aparece depois do webhook assinado (D13).
Dados pessoais (documento, telefone, e-mail, endereço exato) nunca saem daqui.
"""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal, InvalidOperation
from enum import StrEnum
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt

from trato.api import rotas_app
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.repositorios import Contrato
from trato.api.repositorios_app import NotaMaterial, PedidoAberto, RecusaPedido
from trato.api.rotas_app import AvaliacaoOut, AvaliarIn, PedidoAbertoOut, PerfilOut
from trato.api.servicos import carregar_pedido
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.orquestrador import ErroFluxo, ServicoPagamento
from trato.pedidos.estados import Estado, Pedido
from trato.persistencia.erros import NaoEncontrado
from trato.persistencia.usuarios import nome_de_exibicao
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_texto

router = APIRouter(prefix="/v1", tags=["app"])

TETO_CENTAVOS = 10**10
ESTADOS_COBRAVEIS = (Estado.ORCAMENTO_ACEITO, Estado.AGUARDANDO_CONFIRMACAO)


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- Saídas -----------------------------------------------------------------------------


class ItemOrcamentoOut(BaseModel):
    tipo: str
    descricao: str
    quantidade: str = Field(description="Decimal em texto, ex.: `1.50`.")
    valor_unitario_centavos: int
    total_centavos: int


class OrcamentoDetalheOut(BaseModel):
    id: str
    pedido_id: str
    profissional_id: str
    profissional_nome: str | None
    versao: int
    status: str
    valor_centavos: int
    prazo_execucao_dias: int | None
    validade_ate: datetime | None
    garantia_dias: int | None
    fora_do_escopo: str | None
    sinal_material_centavos: int | None
    observacoes: str | None
    enviado_em: datetime | None
    aceito: bool
    itens: list[ItemOrcamentoOut]


class CobrancaContratoOut(BaseModel):
    contrato_id: str
    cobranca_id: str
    estado_pagamento: str = Field(description="Sempre `aguardando_confirmacao` aqui; nunca `pago`.")
    meio: str
    valor_centavos: int
    tipo_instrucao: str = Field(description="`pix_copia_e_cola` ou `cartao_segredo_do_cliente`.")
    instrucao: str | None = Field(None, description="O que o app usa para pagar.")
    criada_em: datetime


class PagamentoContratoOut(BaseModel):
    contrato_id: str
    estado_pagamento: str = Field(
        description="`sem_cobranca`, `aguardando_confirmacao`, `pago`, `falhou` ou `cancelada`."
    )
    pago: bool = Field(description="Verdadeiro só depois do webhook assinado do provedor.")
    valor_centavos: int | None
    pago_centavos: int
    cobranca_id: str | None = None
    meio: str | None = None
    estado_pedido: str


class RetrabalhoOut(BaseModel):
    aberto_em: datetime
    atender_ate: datetime
    estado: str


class GarantiaOut(BaseModel):
    contrato_id: str
    iniciada: bool
    ativa: bool
    dias: int | None
    inicio_em: datetime | None
    fim_em: datetime | None
    retrabalhos: list[RetrabalhoOut]


class AditivoContratoOut(BaseModel):
    id: str
    contrato_id: str
    descricao: str
    valor_centavos: int
    estado: str = Field(description="`proposto`, `aprovado`, `recusado` ou `pago`.")


class AditivoDecididoOut(BaseModel):
    aditivo: AditivoContratoOut
    cobranca: CobrancaContratoOut | None = Field(
        None, description="Só quando o aditivo foi aprovado e o serviço de pagamento está ligado."
    )


class ItemNotaOut(BaseModel):
    descricao: str
    quantidade: str
    valor_unitario_centavos: int
    total_centavos: int


class NotaMaterialOut(BaseModel):
    id: str
    contrato_id: str
    itens: list[ItemNotaOut]
    total_centavos: int
    enviada_em: datetime


class RecusaOut(BaseModel):
    pedido_id: str
    recusado: bool = True


# --- Entradas ---------------------------------------------------------------------------


class CobrarContratoIn(_Entrada):
    meio: MeioPagamento


class AditivoNovoIn(_Entrada):
    descricao: str = Field(min_length=1, max_length=1000)
    valor_centavos: StrictInt = Field(gt=0, le=TETO_CENTAVOS)


class AprovarAditivoContratoIn(_Entrada):
    meio: MeioPagamento = MeioPagamento.PIX


class ItemNotaIn(_Entrada):
    descricao: str = Field(min_length=1, max_length=200)
    quantidade: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    valor_unitario_centavos: StrictInt = Field(ge=0, le=TETO_CENTAVOS)


class NotaMaterialIn(_Entrada):
    foto_storage_path: str = Field(
        min_length=3, max_length=300, description="Caminho da foto da notinha no bucket privado."
    )
    itens: list[ItemNotaIn] = Field(min_length=1, max_length=50)


class RecusarIn(_Entrada):
    motivo: str = Field(min_length=1, max_length=500)


class AtualizarPerfilIn(_Entrada):
    nome: str = Field(min_length=2, max_length=120)


# --- Apoio ------------------------------------------------------------------------------


def _servico(request: Request) -> ServicoPagamento:
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is None:
        raise HTTPException(503, "Pagamento ainda não configurado.")
    return servico


def _contrato_do_usuario(
    contexto: Contexto, contrato_id: str, usuario: Usuario
) -> tuple[Pedido, Contrato]:
    """O contrato (um por pedido) de quem faz parte dele. Os demais recebem 404."""
    pedido = carregar_pedido(contexto, contrato_id, usuario)
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    if contrato is None:
        raise HTTPException(404, "Este pedido ainda não tem contrato.")
    return pedido, contrato


def _cobranca_out(contrato_id: str, cobranca) -> CobrancaContratoOut:
    pix = cobranca.meio is MeioPagamento.PIX
    return CobrancaContratoOut(
        contrato_id=contrato_id,
        cobranca_id=cobranca.id,
        estado_pagamento="aguardando_confirmacao",
        meio=cobranca.meio.value,
        valor_centavos=cobranca.valor_centavos,
        tipo_instrucao="pix_copia_e_cola" if pix else "cartao_segredo_do_cliente",
        instrucao=cobranca.instrucao,
        criada_em=cobranca.criada_em,
    )


# --- Orçamento --------------------------------------------------------------------------


@router.get(
    "/orcamentos/{orcamento_id}",
    response_model=OrcamentoDetalheOut,
    summary="Detalhe de um orçamento enviado",
    description="Itens, validade e o que está fora do escopo. Só o cliente do pedido e o "
    "profissional autor veem; rascunho nunca aparece.",
)
def detalhe_do_orcamento(
    orcamento_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> OrcamentoDetalheOut:
    orc = contexto.orcamentos.detalhe(orcamento_id)
    pedido = contexto.pedidos.obter(orc.pedido_id) if orc else None
    if orc is None or pedido is None:
        raise HTTPException(404, "Orçamento não encontrado.")
    dono = usuario.papel is PapelUsuario.CLIENTE and pedido.cliente_id == usuario.id
    autor = usuario.papel is PapelUsuario.PROFISSIONAL and orc.profissional_id == usuario.id
    if not (dono or autor):
        raise HTTPException(404, "Orçamento não encontrado.")
    campos = {k: v for k, v in vars(orc).items() if k != "itens"}
    return OrcamentoDetalheOut(
        **campos,
        aceito=orc.id == pedido.orcamento_id,
        itens=[ItemOrcamentoOut(**vars(i)) for i in orc.itens],
    )


# --- Cobrança e estado do pagamento -----------------------------------------------------


@router.post(
    "/contratos/{contrato_id}/cobranca",
    response_model=CobrancaContratoOut,
    status_code=201,
    summary="Criar a cobrança do contrato (Pix ou cartão)",
    description=(
        "Cria a cobrança no provedor com chave de idempotência (repetir devolve a mesma cobrança "
        "pendente). Devolve `aguardando_confirmacao` e o que o app usa para pagar. O pedido só "
        "vira pago depois do webhook assinado: consulte `GET .../pagamento`."
    ),
)
def criar_cobranca(
    contrato_id: str,
    corpo: CobrarContratoIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> CobrancaContratoOut:
    servico = _servico(request)
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if pedido.estado not in ESTADOS_COBRAVEIS or pedido.referencia_pagamento is not None:
        raise HTTPException(409, "O pedido não está esperando pagamento.")
    cobranca = servico.cobrar(contexto, pedido, contrato.valor_centavos, corpo.meio)
    return _cobranca_out(pedido.id, cobranca)


@router.get(
    "/contratos/{contrato_id}/pagamento",
    response_model=PagamentoContratoOut,
    summary="Estado do pagamento (o app consulta até o webhook confirmar)",
    description="`pago` só é verdadeiro depois do webhook assinado do provedor; a cobrança "
    "criada ou o aviso do cliente não bastam (D13).",
)
def estado_do_pagamento(
    contrato_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> PagamentoContratoOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    servico = getattr(request.app.state, "servico_pagamento", None)
    principal = None
    if servico is not None:
        principais = [c for c in servico.cobrancas.do_pedido(pedido.id) if c.aditivo_id is None]
        principal = principais[-1] if principais else None
    pago = pedido.referencia_pagamento is not None  # prova gravada pelo webhook assinado
    if pago:
        estado = "pago"
    elif principal is None:
        estado = "sem_cobranca"
    elif principal.status is EstadoCobranca.FALHOU:
        estado = "falhou"
    elif principal.status is EstadoCobranca.CANCELADA:
        estado = "cancelada"
    else:
        estado = "aguardando_confirmacao"
    return PagamentoContratoOut(
        contrato_id=pedido.id,
        estado_pagamento=estado,
        pago=pago,
        valor_centavos=contrato.valor_centavos,
        pago_centavos=saldo.cliente_pagou,
        cobranca_id=principal.id if principal else None,
        meio=principal.meio.value if principal else None,
        estado_pedido=pedido.estado.value,
    )


# --- Garantia ---------------------------------------------------------------------------


@router.get(
    "/contratos/{contrato_id}/garantia",
    response_model=GarantiaOut,
    summary="Garantia do serviço concluído",
)
def garantia_do_contrato(
    contrato_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> GarantiaOut:
    pedido, _ = _contrato_do_usuario(contexto, contrato_id, usuario)
    garantia = contexto.garantias.obter_garantia(pedido.id)
    retrabalhos = [
        RetrabalhoOut(aberto_em=r.aberto_em, atender_ate=r.atender_ate, estado=str(r.estado.value))
        for r in contexto.garantias.retrabalhos(pedido.id)
    ]
    if garantia is None:
        return GarantiaOut(
            contrato_id=pedido.id, iniciada=False, ativa=False, dias=None, inicio_em=None,
            fim_em=None, retrabalhos=retrabalhos,
        )  # fmt: skip
    agora = contexto.agora()
    return GarantiaOut(
        contrato_id=pedido.id,
        iniciada=True,
        ativa=garantia.inicio_em <= agora <= garantia.fim_em,
        dias=garantia.dias,
        inicio_em=garantia.inicio_em,
        fim_em=garantia.fim_em,
        retrabalhos=retrabalhos,
    )


# --- Aditivos ---------------------------------------------------------------------------

_ESTADO_DO_BANCO = {"pendente": "proposto", "aprovado": "aprovado", "recusado": "recusado"}


def _aditivos_do_contrato(
    request: Request, contexto: Contexto, pedido: Pedido
) -> list[AditivoContratoOut]:
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is not None:
        itens = [(a.id, a.descricao, a.valor_centavos, a.estado.value) for a in
                 servico.aditivos.do_pedido(pedido.id)]  # fmt: skip
    elif "execucao" in contexto.extras:
        itens = [
            (a.id, a.motivo, a.valor_centavos, _ESTADO_DO_BANCO.get(a.status, a.status))
            for a in contexto.extras["execucao"].aditivos_do_pedido(pedido.id)
        ]
    else:
        raise HTTPException(503, "Aditivos ainda não configurados.")
    return [
        AditivoContratoOut(id=i, contrato_id=pedido.id, descricao=d, valor_centavos=v, estado=e)
        for i, d, v, e in itens
    ]


@router.get(
    "/contratos/{contrato_id}/aditivos",
    response_model=list[AditivoContratoOut],
    summary="Aditivos do contrato",
)
def listar_aditivos(
    contrato_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[AditivoContratoOut]:
    pedido, _ = _contrato_do_usuario(contexto, contrato_id, usuario)
    return _aditivos_do_contrato(request, contexto, pedido)


@router.post(
    "/contratos/{contrato_id}/aditivos",
    response_model=AditivoContratoOut,
    status_code=201,
    summary="Profissional propõe um aditivo (nada é cobrado ainda)",
)
def propor_aditivo(
    contrato_id: str,
    corpo: AditivoNovoIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoContratoOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if contrato.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional contratado neste pedido pode propor aditivo.")
    if pedido.estado is not Estado.EM_ANDAMENTO:
        raise HTTPException(409, "Só dá para propor aditivo com o serviço em andamento.")
    descricao = limpar_texto(
        corpo.descricao, "descrição", obter_config_seguranca().comentario_max_chars
    )
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is not None:
        try:
            novo = servico.propor_aditivo(contexto, pedido, descricao, corpo.valor_centavos)
        except ErroFluxo as erro:
            raise HTTPException(erro.status, str(erro)) from erro
        return AditivoContratoOut(
            id=novo.id, contrato_id=pedido.id, descricao=novo.descricao,
            valor_centavos=novo.valor_centavos, estado=novo.estado.value,
        )  # fmt: skip
    if "execucao" not in contexto.extras:
        raise HTTPException(503, "Aditivos ainda não configurados.")
    novo_id = contexto.extras["execucao"].propor_aditivo(
        pedido.id, usuario.id, descricao, corpo.valor_centavos
    )
    return AditivoContratoOut(
        id=novo_id, contrato_id=pedido.id, descricao=descricao,
        valor_centavos=corpo.valor_centavos, estado="proposto",
    )  # fmt: skip


def _decidir_aditivo(
    request: Request,
    contexto: Contexto,
    usuario: Usuario,
    contrato_id: str,
    aditivo_id: str,
    aprovar: bool,
    meio: MeioPagamento,
) -> AditivoDecididoOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if pedido.cliente_id != usuario.id:  # só o cliente decide
        raise HTTPException(403, "Só o cliente decide sobre o aditivo.")
    if pedido.estado is not Estado.EM_ANDAMENTO:
        raise HTTPException(409, "Só dá para decidir aditivo com o serviço em andamento.")
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is not None:
        try:
            if aprovar:
                aditivo, cobranca = servico.aprovar_aditivo(contexto, pedido, aditivo_id, meio)
                return AditivoDecididoOut(
                    aditivo=AditivoContratoOut(
                        id=aditivo.id,
                        contrato_id=pedido.id,
                        descricao=aditivo.descricao,
                        valor_centavos=aditivo.valor_centavos,
                        estado=aditivo.estado.value,
                    ),  # fmt: skip
                    cobranca=_cobranca_out(pedido.id, cobranca),
                )
            aditivo = servico.recusar_aditivo(contexto, pedido, aditivo_id)
        except ErroFluxo as erro:
            raise HTTPException(erro.status, str(erro)) from erro
        return AditivoDecididoOut(
            aditivo=AditivoContratoOut(
                id=aditivo.id,
                contrato_id=pedido.id,
                descricao=aditivo.descricao,
                valor_centavos=aditivo.valor_centavos,
                estado=aditivo.estado.value,
            )  # fmt: skip
        )
    if "execucao" not in contexto.extras:
        raise HTTPException(503, "Aditivos ainda não configurados.")
    atual = next(
        (a for a in _aditivos_do_contrato(request, contexto, pedido) if a.id == aditivo_id), None
    )
    if atual is None:
        raise HTTPException(404, "Aditivo não encontrado.")
    if atual.estado != "proposto":
        raise HTTPException(409, "Este aditivo já foi decidido.")
    try:
        contexto.extras["execucao"].decidir_aditivo(
            aditivo_id, usuario.id, aprovar, contexto.agora()
        )
    except NaoEncontrado as erro:
        raise HTTPException(404, "Aditivo não encontrado.") from erro
    return AditivoDecididoOut(
        aditivo=atual.model_copy(update={"estado": "aprovado" if aprovar else "recusado"})
    )


@router.post(
    "/contratos/{contrato_id}/aditivos/{aditivo_id}/aprovar",
    response_model=AditivoDecididoOut,
    summary="Cliente aprova o aditivo",
    description="Só o cliente do contrato. Com o serviço de pagamento ligado, a cobrança do "
    "aditivo é criada e fica `aguardando_confirmacao` até o webhook.",
)
def aprovar_aditivo(
    contrato_id: str,
    aditivo_id: str,
    request: Request,
    corpo: AprovarAditivoContratoIn | None = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoDecididoOut:
    meio = corpo.meio if corpo else MeioPagamento.PIX
    return _decidir_aditivo(request, contexto, usuario, contrato_id, aditivo_id, True, meio)


@router.post(
    "/contratos/{contrato_id}/aditivos/{aditivo_id}/recusar",
    response_model=AditivoDecididoOut,
    summary="Cliente recusa o aditivo",
)
def recusar_aditivo(
    contrato_id: str,
    aditivo_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoDecididoOut:
    return _decidir_aditivo(
        request, contexto, usuario, contrato_id, aditivo_id, False, MeioPagamento.PIX
    )


# --- Nota de material -------------------------------------------------------------------


def _caminho_da_foto_valido(caminho: str) -> bool:
    partes = caminho.split("/")
    return not ("://" in caminho or ".." in partes or caminho.startswith("/") or "" in partes)


def _nota_out(nota: NotaMaterial) -> NotaMaterialOut:
    return NotaMaterialOut(
        id=nota.id,
        contrato_id=nota.pedido_id,
        itens=[
            ItemNotaOut(descricao=d, quantidade=q, valor_unitario_centavos=u, total_centavos=t)
            for d, q, u, t in nota.itens
        ],  # fmt: skip
        total_centavos=nota.total_centavos,
        enviada_em=nota.enviada_em,
    )


@router.post(
    "/contratos/{contrato_id}/notas-material",
    response_model=NotaMaterialOut,
    status_code=201,
    summary="Profissional envia a nota de material (foto da notinha + itens)",
    description="O total é calculado aqui (quantidade x unitário, meio para cima), nunca pelo app.",
)
def enviar_nota_material(
    contrato_id: str,
    corpo: NotaMaterialIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> NotaMaterialOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if contrato.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional contratado neste pedido envia nota.")
    if pedido.estado is not Estado.EM_ANDAMENTO:
        raise HTTPException(409, "Só dá para enviar nota com o serviço em andamento.")
    if not _caminho_da_foto_valido(corpo.foto_storage_path):
        raise HTTPException(422, "O caminho da foto não é válido.")
    seguranca = obter_config_seguranca()
    linhas = []
    for item in corpo.itens:
        try:
            total = int((item.quantidade * item.valor_unitario_centavos).to_integral_value(
                rounding="ROUND_HALF_UP"))  # fmt: skip
        except InvalidOperation as erro:
            raise HTTPException(422, "Quantidade inválida.") from erro
        linhas.append(
            (
                limpar_texto(item.descricao, "item", 200, seguranca),
                format(item.quantidade, "f"),
                item.valor_unitario_centavos,
                total,
            )
        )
    total_nota = sum(t for *_, t in linhas)
    if total_nota > TETO_CENTAVOS:
        raise HTTPException(422, "O total da nota é alto demais.")
    nota = contexto.notas_material.registrar(
        NotaMaterial(
            "",
            pedido.id,
            usuario.id,
            corpo.foto_storage_path,
            tuple(linhas),
            total_nota,
            contexto.agora(),
        )  # fmt: skip
    )
    return _nota_out(nota)


@router.get(
    "/contratos/{contrato_id}/notas-material",
    response_model=list[NotaMaterialOut],
    summary="Notas de material do contrato",
)
def listar_notas_material(
    contrato_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[NotaMaterialOut]:
    pedido, _ = _contrato_do_usuario(contexto, contrato_id, usuario)
    return [_nota_out(n) for n in contexto.notas_material.do_pedido(pedido.id)]


# --- Avaliação --------------------------------------------------------------------------


@router.post(
    "/contratos/{contrato_id}/avaliacao",
    response_model=AvaliacaoOut,
    status_code=201,
    summary="Avaliar o serviço concluído (mesma regra de `/pedidos/{id}/avaliacao`)",
)
def avaliar_contrato(
    contrato_id: str,
    corpo: AvaliarIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AvaliacaoOut:
    return rotas_app.avaliar(contrato_id, corpo, usuario, contexto)


# --- Pedidos abertos e recusa -----------------------------------------------------------


class OrdemPedidos(StrEnum):
    RECENTES = "recentes"
    ANTIGOS = "antigos"
    URGENTES = "urgentes"
    MAIOR_VALOR = "maior_valor"
    MENOR_VALOR = "menor_valor"


def _teto_da_faixa(p: PedidoAberto) -> int:
    return p.faixa_preco_max_centavos if p.faixa_preco_max_centavos is not None else -1


@router.get(
    "/profissional/pedidos-abertos",
    response_model=list[PedidoAbertoOut],
    summary="Pedidos abertos que combinam com o profissional",
    description=(
        "Mesma regra de visibilidade da RLS: profissional aprovado, categoria que atua e não "
        "está suspensa, região atendida. Os pedidos que ele recusou não voltam. Filtros: "
        "`categoria_id`, `bairro`, faixa de preço (`preco_min_centavos` e `preco_max_centavos` "
        "pegam pedidos cuja faixa cruza o intervalo; pedido sem faixa sempre entra) e `ordenar`."
    ),
)
def pedidos_abertos(
    categoria_id: Annotated[str | None, Query()] = None,
    bairro: Annotated[str | None, Query(max_length=120)] = None,
    preco_min_centavos: Annotated[int | None, Query(ge=0, le=TETO_CENTAVOS)] = None,
    preco_max_centavos: Annotated[int | None, Query(ge=0, le=TETO_CENTAVOS)] = None,
    ordenar: OrdemPedidos = OrdemPedidos.RECENTES,
    limite: Annotated[int, Query(ge=1, le=100)] = 50,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoAbertoOut]:
    if (
        preco_min_centavos is not None
        and preco_max_centavos is not None
        and preco_min_centavos > preco_max_centavos
    ):
        raise HTTPException(422, "O preço mínimo não pode passar do máximo.")
    recusados = {r.pedido_id for r in contexto.recusas.do_profissional(usuario.id)}
    itens = [p for p in contexto.pedidos.listar_abertos(usuario.id) if p.id not in recusados]
    if categoria_id:
        itens = [p for p in itens if p.categoria_id == categoria_id]
    if bairro:
        alvo = bairro.strip().casefold()
        itens = [p for p in itens if (p.bairro or "").strip().casefold() == alvo]
    if preco_min_centavos is not None:
        minimo = preco_min_centavos
        itens = [
            p
            for p in itens
            if p.faixa_preco_max_centavos is None or p.faixa_preco_max_centavos >= minimo
        ]
    if preco_max_centavos is not None:
        maximo = preco_max_centavos
        itens = [
            p
            for p in itens
            if p.faixa_preco_min_centavos is None or p.faixa_preco_min_centavos <= maximo
        ]
    if ordenar is OrdemPedidos.ANTIGOS:
        itens.sort(key=lambda p: p.aberto_em)
    elif ordenar is OrdemPedidos.URGENTES:
        itens.sort(key=lambda p: (not p.urgente, -p.aberto_em.timestamp()))
    elif ordenar is OrdemPedidos.MAIOR_VALOR:
        itens.sort(key=lambda p: (-_teto_da_faixa(p), -p.aberto_em.timestamp()))
    elif ordenar is OrdemPedidos.MENOR_VALOR:
        itens.sort(
            key=lambda p: (
                p.faixa_preco_min_centavos if p.faixa_preco_min_centavos is not None else 10**18,
                -p.aberto_em.timestamp(),
            )
        )
    else:
        itens.sort(key=lambda p: p.aberto_em, reverse=True)
    return [PedidoAbertoOut(**vars(p)) for p in itens[:limite]]


@router.post(
    "/pedidos/{pedido_id}/recusar",
    response_model=RecusaOut,
    summary="Profissional recusa um pedido aberto",
    description="Tira o pedido da lista dele; o cliente não é avisado e o pedido não muda de "
    "estado. Só vale para pedido que ele podia ver (aberto, categoria e região). Repetir é seguro.",
)
def recusar_pedido(
    pedido_id: str,
    corpo: RecusarIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecusaOut:
    visivel = any(p.id == pedido_id for p in contexto.pedidos.listar_abertos(usuario.id))
    ja_recusou = any(r.pedido_id == pedido_id for r in contexto.recusas.do_profissional(usuario.id))
    if not (visivel or ja_recusou):
        raise HTTPException(404, "Pedido não encontrado.")
    motivo = limpar_texto(corpo.motivo, "motivo", 500, obter_config_seguranca())
    contexto.recusas.recusar(RecusaPedido(pedido_id, usuario.id, motivo, contexto.agora()))
    return RecusaOut(pedido_id=pedido_id)


# --- Perfil -----------------------------------------------------------------------------


def _perfil_out(contexto: Contexto, usuario: Usuario) -> PerfilOut:
    detalhe = contexto.usuarios.detalhe(usuario.id)
    if detalhe is None:
        contexto.usuarios.garantir(usuario.id)  # idempotente
        detalhe = contexto.usuarios.detalhe(usuario.id)
    if detalhe is None:  # id que não existe no provedor de login
        raise HTTPException(404, "Perfil não encontrado.")
    tem_perfil = usuario.papel is PapelUsuario.PROFISSIONAL or (
        usuario.papel is PapelUsuario.CLIENTE
        and contexto.usuarios.tem_perfil_profissional(usuario.id)
    )
    papeis = [usuario.papel.value]
    if tem_perfil and "profissional" not in papeis:
        papeis.append("profissional")
    if usuario.papel is PapelUsuario.PROFISSIONAL and "cliente" not in papeis:
        papeis.insert(0, "cliente")  # quem é profissional também pode pedir serviço
    return PerfilOut(
        id=detalhe.id,
        nome=detalhe.nome,
        papel=usuario.papel.value,
        status=detalhe.status,
        nivel_verificacao=detalhe.nivel_verificacao,
        nota_publica=detalhe.nota_publica,
        servicos_concluidos=detalhe.servicos_concluidos,
        papeis=papeis,
        tem_perfil_profissional=tem_perfil,
        status_verificacao=contexto.usuarios.status_verificacao(usuario.id) if tem_perfil else None,
    )


@router.get("/me", response_model=PerfilOut, summary="Meu perfil")
def meu_perfil(
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PerfilOut:
    return _perfil_out(contexto, usuario)


@router.patch("/me", response_model=PerfilOut, summary="Atualizar meu perfil (nome)")
def atualizar_perfil(
    corpo: AtualizarPerfilIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> PerfilOut:
    nome = nome_de_exibicao(corpo.nome)
    contexto.usuarios.garantir(usuario.id, nome)
    contexto.usuarios.atualizar_nome(usuario.id, nome)
    return _perfil_out(contexto, usuario)


def registrar_rotas(app: FastAPI) -> FastAPI:
    app.include_router(router)
    return app
