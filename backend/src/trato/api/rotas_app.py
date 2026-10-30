"""Rotas que o app pede: orçamentos do pedido, valores do pagamento, mensagens, notificações,
perfil, pedidos abertos, resumo de orçamento, verificação do profissional e avaliação.

Nenhuma regra de dinheiro mora aqui: a taxa vem do `ProvedorTaxa` (configuração) e o app só
pede e mostra. Dados pessoais (documento, telefone, e-mail, endereço exato) nunca saem daqui.
"""

from __future__ import annotations

from datetime import date, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.repositorios_app import (
    NIVEIS_VERIFICACAO,
    TIPOS_DOCUMENTO,
    Avaliacao,
    DocumentoVerificacao,
    PerfilDetalhe,
)
from trato.api.servicos import carregar_pedido, eh_participante
from trato.pagamentos.custo import MeioPagamento
from trato.pedidos.estados import Estado, Pedido

router = APIRouter(prefix="/v1", tags=["app"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- Saídas -----------------------------------------------------------------------------


class OrcamentoOut(BaseModel):
    id: str
    profissional_id: str
    profissional_nome: str | None
    versao: int
    valor_centavos: int
    prazo_execucao_dias: int | None
    garantia_dias: int | None
    observacoes: str | None
    enviado_em: datetime | None
    aceito: bool


class PagamentoValoresOut(BaseModel):
    pedido_id: str
    estado: str
    valor_centavos: int | None = Field(None, description="Valor do contrato, em centavos.")
    pago_centavos: int = Field(description="O que o ledger mostra como pago (webhook assinado).")
    pagamento_confirmado: bool
    meios_disponiveis: list[str]
    cobranca_pendente_id: str | None = None


class MensagemOut(BaseModel):
    id: int
    autor_id: str
    minha: bool
    texto: str
    mascarada: bool
    enviada_em: datetime
    lida_em: datetime | None


class NotificacaoOut(BaseModel):
    id: str
    tipo: str
    titulo: str
    corpo: str | None
    dados: dict
    criada_em: datetime
    lida: bool


class PerfilOut(BaseModel):
    id: str
    nome: str | None
    papel: str
    status: str
    nivel_verificacao: str | None
    nota_publica: float | None
    servicos_concluidos: int | None


class PedidoAbertoOut(BaseModel):
    id: str
    titulo: str
    descricao: str
    bairro: str | None
    categoria_id: str | None
    faixa_preco_min_centavos: int | None
    faixa_preco_max_centavos: int | None
    urgente: bool
    prazo_desejado: date | None
    aberto_em: datetime


class ResumoOrcamentoOut(BaseModel):
    valor_centavos: int
    taxa_centavos: int
    liquido_centavos: int


class VerificacaoOut(BaseModel):
    id: str
    nivel_solicitado: str
    status: str
    enviada_em: datetime
    documentos: list[str] = Field(description="Só os tipos enviados; os arquivos ficam privados.")


class AvaliacaoOut(BaseModel):
    pedido_id: str
    direcao: str
    nota_geral: int
    comentario: str | None
    etiquetas: list[str]
    criada_em: datetime


# --- Entradas ---------------------------------------------------------------------------


class EnviarMensagemIn(_Entrada):
    texto: str = Field(min_length=1, max_length=2000)


class ResumoOrcamentoIn(_Entrada):
    valor_centavos: StrictInt = Field(
        gt=0, le=10**10, description="Total do orçamento, em centavos."
    )


class DocumentoIn(_Entrada):
    tipo: str
    storage_path: str = Field(
        min_length=3,
        max_length=300,
        description="Caminho do arquivo no bucket privado `verificacao`, não uma URL.",
    )


class VerificacaoIn(_Entrada):
    nivel_solicitado: str = "verificado"
    consentimento_lgpd: StrictBool
    documentos: list[DocumentoIn] = Field(min_length=1, max_length=12)


class AvaliarIn(_Entrada):
    nota_geral: StrictInt = Field(ge=1, le=5)
    comentario: str | None = Field(None, max_length=1000)
    etiquetas: list[str] = Field(default_factory=list, max_length=8)


# --- Acesso -----------------------------------------------------------------------------


def _pedido_visivel(
    contexto: Contexto,
    pedido_id: str,
    usuario: Usuario,
    request: Request | None = None,
    *,
    equipe: tuple[Permissao, ...] = (),
    consulta: str = "pedido",
    com_disputa: bool = False,
) -> Pedido:
    """Como `carregar_pedido`, mas o profissional também vê pedido ABERTO (para orçar/conversar).

    A equipe só passa pela matriz de permissões (`equipe=`); `com_disputa` ainda exige que o
    pedido tenha disputa (o chat só é do mediador que está julgando)."""
    if usuario.papel is PapelUsuario.EQUIPE:
        pedido = carregar_pedido(
            contexto, pedido_id, usuario, request=request, equipe=equipe, consulta=consulta
        )
        if com_disputa and contexto.disputas.obter(pedido.id) is None:
            raise HTTPException(403, "Seu papel na equipe não permite isso.")
        return pedido
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if eh_participante(pedido, usuario):
        return pedido
    if usuario.papel is PapelUsuario.PROFISSIONAL and pedido.estado is Estado.ABERTO:
        return pedido
    raise HTTPException(404, "Pedido não encontrado.")


# --- Orçamentos e pagamento -------------------------------------------------------------


@router.get(
    "/pedidos/{pedido_id}/orcamentos",
    response_model=list[OrcamentoOut],
    summary="Orçamentos recebidos pelo pedido",
    description="O cliente (dono) e a equipe veem todos; o profissional vê só o próprio.",
)
def listar_orcamentos(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[OrcamentoOut]:
    pedido = _pedido_visivel(
        contexto,
        pedido_id,
        usuario,
        request,
        equipe=(Permissao.PEDIDOS_BUSCAR,),
        consulta="orcamentos",
    )
    itens = contexto.orcamentos.do_pedido(pedido.id)
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        itens = [o for o in itens if o.profissional_id == usuario.id]
    return [
        OrcamentoOut(
            id=o.id,
            profissional_id=o.profissional_id,
            profissional_nome=o.profissional_nome,
            versao=o.versao,
            valor_centavos=o.valor_centavos,
            prazo_execucao_dias=o.prazo_execucao_dias,
            garantia_dias=o.garantia_dias,
            observacoes=o.observacoes,
            enviado_em=o.enviado_em,
            aceito=o.id == pedido.orcamento_id,
        )
        for o in itens
    ]


@router.get(
    "/pedidos/{pedido_id}/pagamento",
    response_model=PagamentoValoresOut,
    summary="Valores do pagamento (o que o app mostra antes de pagar)",
)
def valores_do_pagamento(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.EQUIPE)),
    contexto: Contexto = Depends(obter_contexto),
) -> PagamentoValoresOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="pagamento",
    )
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    servico = getattr(request.app.state, "servico_pagamento", None)
    pendente = None
    if servico is not None:
        pendente = next(
            (
                c.id
                for c in servico.cobrancas.do_pedido(pedido.id)
                if c.status.value == "aguardando"
            ),
            None,
        )
    return PagamentoValoresOut(
        pedido_id=pedido.id,
        estado=pedido.estado.value,
        valor_centavos=contrato.valor_centavos if contrato else None,
        pago_centavos=saldo.cliente_pagou,
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        meios_disponiveis=[m.value for m in MeioPagamento],
        cobranca_pendente_id=pendente,
    )


@router.post(
    "/orcamentos/resumo",
    response_model=ResumoOrcamentoOut,
    summary="Taxa e líquido de um valor (calculadora do profissional)",
    description="Só o backend calcula a taxa, pela configuração vigente. Nada é gravado.",
)
def resumo_do_orcamento(
    corpo: ResumoOrcamentoIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ResumoOrcamentoOut:
    if contexto.taxa is None:
        raise HTTPException(503, "A taxa ainda não foi configurada.")
    taxa = min(contexto.taxa.calcular(corpo.valor_centavos), corpo.valor_centavos)
    return ResumoOrcamentoOut(
        valor_centavos=corpo.valor_centavos,
        taxa_centavos=taxa,
        liquido_centavos=corpo.valor_centavos - taxa,
    )


# --- Mensagens --------------------------------------------------------------------------


def _conversa_do_pedido(
    contexto: Contexto, pedido: Pedido, usuario: Usuario, profissional_id: str | None
) -> str:
    """Abre (ou acha) a conversa do pedido com UM profissional."""
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        alvo = usuario.id
    else:
        alvo = profissional_id or pedido.profissional_id
        if alvo is None:
            raise HTTPException(422, "Diga com qual profissional você quer conversar.")
        orcou = any(o.profissional_id == alvo for o in contexto.orcamentos.do_pedido(pedido.id))
        if alvo != pedido.profissional_id and not orcou:
            raise HTTPException(404, "Esse profissional não está neste pedido.")
    return contexto.conversas.abrir(pedido.id, alvo)


def _mensagens_out(contexto: Contexto, conversa: str, usuario: Usuario) -> list[MensagemOut]:
    return [
        MensagemOut(
            id=m.id,
            autor_id=m.autor_id,
            minha=m.autor_id == usuario.id,
            texto=m.texto,
            mascarada=m.mascarada,
            enviada_em=m.enviada_em,
            lida_em=m.lida_em,
        )
        for m in contexto.conversas.listar(conversa)
    ]


@router.get(
    "/pedidos/{pedido_id}/mensagens",
    response_model=list[MensagemOut],
    summary="Mensagens do pedido",
    description=(
        "Para o cliente, `profissional_id` escolhe a conversa (sem ele, vale o profissional "
        "contratado). Antes da contratação, e-mail e telefone saem ocultos."
    ),
)
def listar_mensagens(
    pedido_id: str,
    request: Request,
    profissional_id: Annotated[str | None, Query()] = None,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[MensagemOut]:
    pedido = _pedido_visivel(
        contexto,
        pedido_id,
        usuario,
        request,
        equipe=(Permissao.DISPUTAS_DECIDIR,),
        consulta="chat",
        com_disputa=True,
    )
    conversa = _conversa_do_pedido(contexto, pedido, usuario, profissional_id)
    return _mensagens_out(contexto, conversa, usuario)


@router.post(
    "/pedidos/{pedido_id}/mensagens",
    response_model=MensagemOut,
    status_code=201,
    summary="Enviar mensagem no pedido",
)
def enviar_mensagem(
    pedido_id: str,
    corpo: EnviarMensagemIn,
    profissional_id: Annotated[str | None, Query()] = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> MensagemOut:
    pedido = _pedido_visivel(contexto, pedido_id, usuario)
    if usuario.papel is PapelUsuario.PROFISSIONAL and (
        pedido.profissional_id not in (None, usuario.id)
    ):
        raise HTTPException(404, "Pedido não encontrado.")
    conversa = _conversa_do_pedido(contexto, pedido, usuario, profissional_id)
    nova = contexto.conversas.enviar(conversa, usuario.id, corpo.texto)
    return next(m for m in _mensagens_out(contexto, conversa, usuario) if m.id == nova)


# --- Notificações, perfil, pedidos abertos ----------------------------------------------


@router.get("/notificacoes", response_model=list[NotificacaoOut], summary="Minhas notificações")
def listar_notificacoes(
    nao_lidas: bool = False,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[NotificacaoOut]:
    return [
        NotificacaoOut(
            id=n.id,
            tipo=n.tipo,
            titulo=n.titulo,
            corpo=n.corpo,
            dados=n.dados,
            criada_em=n.criada_em,
            lida=n.lida_em is not None,
        )
        for n in contexto.notificacoes.listar(usuario.id, nao_lidas)
    ]


@router.get("/me", response_model=PerfilOut, summary="Meu perfil")
def meu_perfil(
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PerfilOut:
    perfil = contexto.usuarios.detalhe(usuario.id) or PerfilDetalhe(usuario.id, None, usuario.papel)
    return PerfilOut(
        id=perfil.id,
        nome=perfil.nome,
        papel=usuario.papel.value,
        status=perfil.status,
        nivel_verificacao=perfil.nivel_verificacao,
        nota_publica=perfil.nota_publica,
        servicos_concluidos=perfil.servicos_concluidos,
    )


@router.get(
    "/profissional/pedidos-abertos",
    response_model=list[PedidoAbertoOut],
    summary="Pedidos abertos que combinam com o profissional",
)
def pedidos_abertos(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoAbertoOut]:
    return [PedidoAbertoOut(**vars(p)) for p in contexto.pedidos.listar_abertos(usuario.id)]


# --- Verificação do profissional --------------------------------------------------------


def _caminho_valido(caminho: str, usuario: Usuario) -> bool:
    partes = caminho.split("/")
    if "://" in caminho or ".." in partes or caminho.startswith("/") or "" in partes:
        return False
    if partes[0] == "verificacao":
        partes = partes[1:]
    return len(partes) >= 2 and partes[0] == usuario.id


def _verificacao_out(v) -> VerificacaoOut:
    return VerificacaoOut(
        id=v.id,
        nivel_solicitado=v.nivel_solicitado,
        status=v.status,
        enviada_em=v.enviada_em,
        documentos=[d.tipo for d in v.documentos],
    )


@router.post(
    "/profissional/verificacao",
    response_model=VerificacaoOut,
    status_code=201,
    summary="Enviar documento e selfie para a verificação",
    description=(
        "Recebe só REFERÊNCIAS dos arquivos (caminho no bucket privado), nunca o arquivo nem "
        "o número do documento. Exige o consentimento LGPD, a frente do documento e a selfie."
    ),
)
def enviar_verificacao(
    corpo: VerificacaoIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> VerificacaoOut:
    if not corpo.consentimento_lgpd:
        raise HTTPException(422, "Precisamos do seu consentimento para tratar seus documentos.")
    if corpo.nivel_solicitado not in NIVEIS_VERIFICACAO:
        raise HTTPException(422, "Nível de verificação inválido.")
    tipos = {d.tipo for d in corpo.documentos}
    if not tipos <= set(TIPOS_DOCUMENTO):
        raise HTTPException(422, "Tipo de documento inválido.")
    if not {"documento_frente", "selfie"} <= tipos:
        raise HTTPException(422, "Envie a frente do documento e uma selfie.")
    if not all(_caminho_valido(d.storage_path, usuario) for d in corpo.documentos):
        raise HTTPException(422, "O caminho de um arquivo não é válido.")
    nova = contexto.verificacoes.enviar(
        usuario.id,
        corpo.nivel_solicitado,
        [DocumentoVerificacao(d.tipo, d.storage_path) for d in corpo.documentos],
        contexto.agora(),
    )
    return _verificacao_out(nova)


@router.get(
    "/profissional/verificacao",
    response_model=list[VerificacaoOut],
    summary="Minhas verificações",
)
def minhas_verificacoes(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[VerificacaoOut]:
    return [_verificacao_out(v) for v in contexto.verificacoes.da_pessoa(usuario.id)]


# --- Avaliação --------------------------------------------------------------------------


@router.post(
    "/pedidos/{pedido_id}/avaliacao",
    response_model=AvaliacaoOut,
    status_code=201,
    summary="Avaliar o serviço concluído",
    description="Cliente avalia o profissional e o profissional avalia o cliente, uma vez cada.",
)
def avaliar(
    pedido_id: str,
    corpo: AvaliarIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AvaliacaoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado is not Estado.CONCLUIDO:
        raise HTTPException(409, "Só dá para avaliar depois que o serviço for concluído.")
    if usuario.papel is PapelUsuario.CLIENTE:
        direcao, avaliado = "cliente_para_profissional", pedido.profissional_id
    else:
        direcao, avaliado = "profissional_para_cliente", pedido.cliente_id
    if avaliado is None:
        raise HTTPException(409, "Este pedido não tem profissional contratado.")
    if contexto.avaliacoes.obter(pedido.id, direcao) is not None:
        raise HTTPException(409, "Você já avaliou este serviço.")
    nova = Avaliacao(
        pedido_id=pedido.id,
        direcao=direcao,
        avaliador_id=usuario.id,
        avaliado_id=avaliado,
        nota_geral=corpo.nota_geral,
        comentario=(corpo.comentario or "").strip() or None,
        etiquetas=tuple(e.strip() for e in corpo.etiquetas if e.strip()),
        criada_em=contexto.agora(),
    )
    contexto.avaliacoes.salvar(nova)
    return AvaliacaoOut(
        pedido_id=nova.pedido_id,
        direcao=nova.direcao,
        nota_geral=nova.nota_geral,
        comentario=nova.comentario,
        etiquetas=list(nova.etiquetas),
        criada_em=nova.criada_em,
    )
