"""Rotas que o app usa em torno do orçamento e do contrato: detalhe do orçamento, cobrança e
estado do pagamento, garantia, aditivos, nota de material, avaliação, perfil e pedidos abertos.

`{contrato_id}` nas rotas é o **id do pedido**: o contrato é um por pedido e não tem outro id.
Nenhuma regra de dinheiro mora aqui: a cobrança do
`ServicoPagamento` e o app só pede e mostra. "Pago" só aparece depois do webhook assinado (D13).
Dados pessoais (documento, telefone, e-mail, endereço exato) nunca saem daqui.
"""

from __future__ import annotations

import logging
import math
import re
import threading
from collections.abc import Mapping
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from enum import StrEnum
from typing import Annotated, Any

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, StrictInt, model_validator

from trato.api import rotas_app
from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_evento, avisar_mensagem_nova, avisar_orcamento_recebido
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.localizacao import na_grade
from trato.api.modelos import JanelaIn, PedidoOut, RespostaPedidoOut
from trato.api.moedas import (
    MOTIVO_ORCAMENTO_ESGOTADO,
    DescontoMoedasIndisponivel,
    calcular_uso_moedas,
    volta_em,
)
from trato.api.repositorios import Contrato, ItemOrcamento
from trato.api.repositorios_app import NotaMaterial, PedidoAberto, RecusaPedido
from trato.api.rotas_app import AvaliacaoOut, AvaliarIn, PedidoAbertoOut, PerfilOut
from trato.api.rotas_pedidos import respostas_out
from trato.api.rotas_upload import urls_fotos_do_pedido
from trato.api.servicos import ator_de, carregar_pedido, nomes_de_categorias, pedido_out
from trato.api.visibilidade import pedido_visivel_ao_profissional
from trato.notificacoes.eventos import Evento
from trato.pagamentos.cupons import (
    limite_por_usuario_do_cupom,
    usos_do_usuario_do_cupom,
    validar_e_calcular_cupom,
)
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.orquestrador import ErroFluxo, ServicoPagamento
from trato.pagamentos.provedor.base import ErroProvedor
from trato.pedidos import estados as pedidos_estados
from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Janela,
    Papel,
    Pedido,
    ProvaAgenda,
    ProvaRemarcacao,
)
from trato.persistencia.erros import NaoEncontrado
from trato.persistencia.usuarios import nome_de_exibicao
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_texto

router = APIRouter(prefix="/v1", tags=["app"])
log = logging.getLogger(__name__)

TETO_CENTAVOS = 10**10
TETO_NOTA_MATERIAL_CENTAVOS = 100_000_000  # R$ 1.000.000,00 (mesmo teto do app)
MAX_QUANTIDADE_ITEM_NOTA = 9999
JANELA_NOTA_DUPLICADA = timedelta(seconds=60)
_TRAVA_COBRANCA_CUPOM = threading.RLock()  # reserva do uso do cupom: checar+cobrar atômicos
_TRAVA_NOTA_MATERIAL = threading.RLock()  # check+gravação da nota atômicos (em memória)
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
    horas_deslocamento: str | None = Field(
        None, description="Horas de deslocamento (soma dos itens `deslocamento`), ex.: `1.5`."
    )
    horas_trabalhadas: str | None = Field(
        None, description="Horas trabalhadas (soma dos itens `horas`), ex.: `3.5`."
    )
    total_horas: str | None = Field(
        None, description="Deslocamento + trabalhadas: o total de horas que o cliente vê."
    )


def somar_horas(itens, tipo: str) -> Decimal | None:  # type: ignore[no-untyped-def]
    """Soma a quantidade dos itens de um tipo (quantidade = horas). None se não há item do tipo."""
    achados = [Decimal(str(i.quantidade)) for i in itens if i.tipo == tipo]
    return sum(achados, Decimal(0)) if achados else None


def _texto_horas(valor: Decimal | None) -> str | None:
    if valor is None:
        return None
    texto = format(valor.normalize(), "f")
    return texto


class CobrancaContratoOut(BaseModel):
    contrato_id: str
    cobranca_id: str
    estado_pagamento: str = Field(description="Sempre `aguardando_confirmacao` aqui; nunca `pago`.")
    meio: str
    valor_centavos: int = Field(
        description="O que o cliente paga: o serviço (+ custo do parcelado)."
    )
    parcelas: int = 1
    tipo_instrucao: str = Field(description="`pix_copia_e_cola` ou `cartao_segredo_do_cliente`.")
    instrucao: str | None = Field(None, description="O que o app usa para pagar.")
    cliente_externo_id: str | None = Field(
        None, description="Cartão: cliente do provedor, para a folha listar e salvar cartões."
    )
    chave_efemera: str | None = Field(
        None, description="Cartão: chave de vida curta da folha de cartão do provedor."
    )
    criada_em: datetime
    desconto_disponivel: bool = Field(
        True, description="Se o desconto de moedas pode ser dado (orçamento e teto do cliente)."
    )
    desconto_indisponivel_motivo: str | None = Field(
        None,
        description="`orcamento_esgotado`, `limite_diario` ou `teto_cliente` quando indisponível.",
    )
    desconto_volta_em: date | None = Field(
        None, description="Quando o desconto volta (Brasília); null se disponível."
    )
    desconto_possivel_centavos: int = Field(
        0, description="Desconto de moedas que seria aplicado neste pedido (sem reservar)."
    )


class PagamentoContratoOut(BaseModel):
    contrato_id: str
    estado_pagamento: str = Field(
        description="`sem_cobranca`, `aguardando_confirmacao`, `pago`, `falhou` ou `cancelada`."
    )
    pago: bool = Field(description="Verdadeiro só depois do webhook assinado do provedor.")
    valor_centavos: int | None = Field(description="O valor do SERVIÇO (o orçamento).")
    total_a_pagar_centavos: int | None = Field(
        None, description="O valor do serviço (à vista). Sem custo de parcelamento."
    )
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
    foto_url: str | None = Field(
        default=None,
        description="URL assinada e curta para abrir a foto da nota. Não guarde.",
    )


class RecusaOut(BaseModel):
    pedido_id: str
    recusado: bool = True


# --- Entradas ---------------------------------------------------------------------------


class CobrarContratoIn(_Entrada):
    meio: MeioPagamento
    parcelas: StrictInt = Field(
        1,
        ge=1,
        le=12,
        description="Só cartão; parcelado desligado até o custo do provedor estar configurado.",
    )
    cupom: str | None = Field(
        default=None, max_length=30, description="Código de cupom de desconto opcional."
    )
    usar_moedas: bool = Field(
        default=False,
        description="Usa moedas do Trato como desconto. O backend escolhe quantas (nunca o app).",
    )


class AplicarCupomIn(_Entrada):
    codigo: str = Field(min_length=1, max_length=30)


TETO_ADITIVO_CENTAVOS = 10_000_000  # R$ 100.000,00


class AditivoNovoIn(_Entrada):
    descricao: str = Field(min_length=1, max_length=1000)
    valor_centavos: StrictInt = Field(gt=0, le=TETO_ADITIVO_CENTAVOS)


class AprovarAditivoContratoIn(_Entrada):
    meio: MeioPagamento = MeioPagamento.PIX


class ItemNotaIn(_Entrada):
    descricao: str = Field(min_length=1, max_length=200)
    quantidade: Decimal = Field(gt=0, le=MAX_QUANTIDADE_ITEM_NOTA, max_digits=10, decimal_places=2)
    valor_unitario_centavos: StrictInt = Field(ge=0, le=TETO_CENTAVOS)


class NotaMaterialIn(_Entrada):
    foto_storage_path: str | None = Field(
        None,
        min_length=3,
        max_length=300,
        description="Caminho da foto da notinha no bucket privado (sem o serviço de upload).",
    )
    midia_id: str | None = Field(
        None,
        min_length=1,
        max_length=64,
        description="`midia_id` devolvido por `POST /v1/uploads/{id}/concluir` (destino "
        "`nota_material`). O backend confere que a mídia é deste pedido e de quem envia.",
    )
    itens: list[ItemNotaIn] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def _uma_foto(self) -> NotaMaterialIn:
        if (self.foto_storage_path is None) == (self.midia_id is None):
            raise ValueError("Mande `midia_id` ou `foto_storage_path` (um dos dois).")
        return self


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
        parcelas=cobranca.parcelas,
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
    dono = pedido.cliente_id == usuario.id
    autor = orc.profissional_id == usuario.id
    if not (dono or autor):
        raise HTTPException(404, "Orçamento não encontrado.")
    campos = {k: v for k, v in vars(orc).items() if k != "itens"}
    desloc = somar_horas(orc.itens, "deslocamento")
    trab = somar_horas(orc.itens, "horas")
    total = None if desloc is None and trab is None else (desloc or Decimal(0)) + (trab or 0)
    return OrcamentoDetalheOut(
        **campos,
        aceito=orc.id == pedido.orcamento_id,
        itens=[ItemOrcamentoOut(**vars(i)) for i in orc.itens],
        horas_deslocamento=_texto_horas(desloc),
        horas_trabalhadas=_texto_horas(trab),
        total_horas=_texto_horas(total),
    )


class RecusarOrcamentoOut(BaseModel):
    orcamento_id: str
    pedido_id: str
    status: str


@router.post(
    "/pedidos/{pedido_id}/orcamentos/{orcamento_id}/recusar",
    response_model=RecusarOrcamentoOut,
    summary="Cliente recusa um orçamento recebido",
    description="Somente o dono do pedido pode recusar. Idempotente se já estiver recusado.",
)
def recusar_orcamento(
    pedido_id: str,
    orcamento_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> RecusarOrcamentoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do pedido pode recusar um orçamento.")
    orc = contexto.orcamentos.detalhe(orcamento_id)
    if orc is None or orc.pedido_id != pedido.id:
        raise HTTPException(404, "Orçamento não encontrado.")
    if orc.status == "aceito":
        raise HTTPException(409, "Este orçamento já foi aceito.")
    if orc.status == "recusado":
        return RecusarOrcamentoOut(orcamento_id=orc.id, pedido_id=pedido.id, status="recusado")
    if orc.status != "enviado":
        raise HTTPException(409, f"Orçamento em estado '{orc.status}' não pode ser recusado.")
    mudou = contexto.orcamentos.recusar(pedido.id, orc.id)
    if mudou:
        notificador = getattr(request.app.state, "notificador", None)
        if notificador is not None:
            notificador.notificar(
                Evento.ORCAMENTO_RECUSADO,
                orc.profissional_id,
                chave=f"orcamento-recusado:{orc.id}",
                pedido_id=pedido.id,
            )
    return RecusarOrcamentoOut(orcamento_id=orc.id, pedido_id=pedido.id, status="recusado")


# --- Cobrança e estado do pagamento -----------------------------------------------------


@router.post(
    "/contratos/{contrato_id}/cupom",
    response_model=rotas_app.PagamentoValoresOut,
    summary="Validar e simular cupom de desconto para o contrato",
)
def aplicar_cupom_contrato(
    contrato_id: str,
    corpo: AplicarCupomIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> rotas_app.PagamentoValoresOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do contrato pode aplicar cupom.")
    servico = _servico(request)
    try:
        aplicado = validar_e_calcular_cupom(
            contexto, corpo.codigo, contrato.valor_centavos, usuario_id=usuario.id
        )
    except ValueError as erro:
        raise HTTPException(422, str(erro)) from None
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    pendente = next(
        (c.id for c in servico.cobrancas.do_pedido(pedido.id) if c.status.value == "aguardando"),
        None,
    )
    conta = servico.total_a_cobrar(contexto, pedido, aplicado.servico_com_desconto_centavos)
    opcoes = [
        rotas_app.OpcaoParcelamentoOut(**vars(o))
        for o in servico.config().parcelamento.opcoes(conta.cobrado_centavos)
    ]
    return rotas_app.PagamentoValoresOut(
        pedido_id=pedido.id,
        estado=pedido.estado.value,
        valor_centavos=contrato.valor_centavos,
        total_a_pagar_centavos=conta.cobrado_centavos,
        opcoes_parcelamento=opcoes,
        pago_centavos=saldo.cliente_pagou,
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        meios_disponiveis=[m.value for m in MeioPagamento],
        cobranca_pendente_id=pendente,
        desconto_centavos=aplicado.desconto_centavos,
        cupom_codigo=aplicado.codigo,
    )


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
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> CobrancaContratoOut | JSONResponse:
    if corpo.cupom and corpo.cupom.strip():
        with _TRAVA_COBRANCA_CUPOM:
            return _criar_cobranca(contrato_id, corpo, request, usuario, contexto)
    return _criar_cobranca(contrato_id, corpo, request, usuario, contexto)


def _criar_cobranca(
    contrato_id: str,
    corpo: CobrarContratoIn,
    request: Request,
    usuario: Usuario,
    contexto: Contexto,
) -> CobrancaContratoOut | JSONResponse:
    servico = _servico(request)
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do contrato pode pagar.")
    if pedido.estado not in ESTADOS_COBRAVEIS or pedido.referencia_pagamento is not None:
        raise HTTPException(409, "O pedido não está esperando pagamento.")
    if not contexto.usuarios.tem_cpf(usuario.id):
        return JSONResponse(
            status_code=422,
            content={
                "detail": "Informe seu CPF para concluir o pagamento.",
                "codigo": "cpf_obrigatorio",
            },
        )
    valor_servico = contrato.valor_centavos
    aplicado = None
    if corpo.cupom and corpo.cupom.strip():
        try:
            aplicado = validar_e_calcular_cupom(
                contexto, corpo.cupom, contrato.valor_centavos, usuario_id=usuario.id
            )
        except ValueError as erro:
            raise HTTPException(422, str(erro)) from None
        if _cupom_ja_reservado(contexto, servico, usuario.id, pedido.id, aplicado.codigo):
            aplicado = None  # o uso permitido já está reservado por outra cobrança pendente
        else:
            valor_servico = aplicado.servico_com_desconto_centavos
    desconto_total = aplicado.desconto_centavos if aplicado else 0
    moedas_usadas = 0
    valor_sem_moedas, desconto_sem_moedas = valor_servico, desconto_total
    uso = calcular_uso_moedas(
        contexto.moedas,
        usuario_id=usuario.id,
        servico_centavos=valor_servico,
        agora=contexto.agora(),
        ignorar=servico.reservas_pendentes_do_pedido(pedido.id),
    )
    possivel = uso.desconto_centavos
    disponivel, motivo, volta = uso.disponivel, uso.motivo, uso.volta_em
    if corpo.usar_moedas:
        moedas_usadas = uso.moedas
        valor_servico -= uso.desconto_centavos
        desconto_total += uso.desconto_centavos
    preparo = None
    if corpo.meio is MeioPagamento.CARTAO and hasattr(servico.provedor, "preparar_cartao"):
        try:
            preparo = servico.provedor.preparar_cartao(usuario.id)
        except ErroProvedor as erro:
            raise HTTPException(
                502, "O parceiro de pagamento não respondeu. Tente de novo."
            ) from erro

    def _cobrar(valor: int, desconto: int, moedas: int):
        try:
            return servico.cobrar(
                contexto,
                pedido,
                valor,
                corpo.meio,
                parcelas=corpo.parcelas,
                cliente_externo=preparo.cliente_id if preparo else None,
                cupom_codigo=aplicado.codigo if aplicado else None,
                desconto_centavos=desconto,
                moedas_usadas=moedas,
            )
        except ErroProvedor as erro:
            raise _recusa_do_provedor(erro, corpo.meio) from erro

    try:
        cobranca = _cobrar(valor_servico, desconto_total, moedas_usadas)
    except DescontoMoedasIndisponivel as indisponivel:
        # Corrida entre pagamentos: o orçamento acabou entre a conta e a reserva. Não é erro: a
        # cobrança sai sem o desconto de moedas, que continuam guardadas.
        cobranca = _cobrar(valor_sem_moedas, desconto_sem_moedas, 0)
        motivo = indisponivel.motivo or MOTIVO_ORCAMENTO_ESGOTADO
        disponivel, volta, possivel = False, volta_em(motivo, contexto.agora()), 0
    saida = _cobranca_out(pedido.id, cobranca)
    saida.desconto_disponivel = disponivel
    saida.desconto_indisponivel_motivo = motivo
    saida.desconto_volta_em = volta
    saida.desconto_possivel_centavos = possivel
    if preparo is not None:
        saida.cliente_externo_id = preparo.cliente_id
        saida.chave_efemera = preparo.chave_efemera
    return saida


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
    servico_a_cobrar = contrato.valor_centavos
    if principal is not None:
        if principal.servico_centavos is not None:
            servico_a_cobrar = principal.servico_centavos
        elif principal.desconto_centavos > 0:
            servico_a_cobrar = max(0, contrato.valor_centavos - principal.desconto_centavos)
    return PagamentoContratoOut(
        contrato_id=pedido.id,
        estado_pagamento=estado,
        pago=pago,
        valor_centavos=contrato.valor_centavos,
        total_a_pagar_centavos=(
            servico.total_a_cobrar(contexto, pedido, servico_a_cobrar).cobrado_centavos
            if servico is not None
            else None
        ),
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
        avisar_evento(
            request, contexto, Evento.ADITIVO_PENDENTE, pedido.cliente_id,
            pedido_id=pedido.id, chave=f"aditivo-proposto:{novo.id}",
        )  # fmt: skip
        return AditivoContratoOut(
            id=novo.id, contrato_id=pedido.id, descricao=novo.descricao,
            valor_centavos=novo.valor_centavos, estado=novo.estado.value,
        )  # fmt: skip
    if "execucao" not in contexto.extras:
        raise HTTPException(503, "Aditivos ainda não configurados.")
    novo_id = contexto.extras["execucao"].propor_aditivo(
        pedido.id, usuario.id, descricao, corpo.valor_centavos
    )
    avisar_evento(
        request, contexto, Evento.ADITIVO_PENDENTE, pedido.cliente_id,
        pedido_id=pedido.id, chave=f"aditivo-proposto:{novo_id}",
    )  # fmt: skip
    return AditivoContratoOut(
        id=novo_id, contrato_id=pedido.id, descricao=descricao,
        valor_centavos=corpo.valor_centavos, estado="proposto",
    )  # fmt: skip


def _avisar_aditivo_aprovado(request: Request, contexto: Contexto, pedido, aditivo_id: str) -> None:  # type: ignore[no-untyped-def]
    if pedido.profissional_id:
        avisar_evento(
            request, contexto, Evento.ADITIVO_APROVADO, pedido.profissional_id,
            pedido_id=pedido.id, chave=f"aditivo-aprovado:{aditivo_id}",
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
                # Cartão: a folha do provedor precisa do cliente e da chave efêmera.
                preparo = None
                if meio is MeioPagamento.CARTAO and hasattr(servico.provedor, "preparar_cartao"):
                    try:
                        preparo = servico.provedor.preparar_cartao(usuario.id)
                    except ErroProvedor as erro:
                        raise HTTPException(
                            502, "O parceiro de pagamento não respondeu. Tente de novo."
                        ) from erro
                aditivo, cobranca = servico.aprovar_aditivo(
                    contexto,
                    pedido,
                    aditivo_id,
                    meio,
                    cliente_externo=preparo.cliente_id if preparo else None,
                )
                saida_cobranca = _cobranca_out(pedido.id, cobranca)
                if preparo is not None:
                    saida_cobranca.cliente_externo_id = preparo.cliente_id
                    saida_cobranca.chave_efemera = preparo.chave_efemera
                _avisar_aditivo_aprovado(request, contexto, pedido, aditivo_id)
                return AditivoDecididoOut(
                    aditivo=AditivoContratoOut(
                        id=aditivo.id,
                        contrato_id=pedido.id,
                        descricao=aditivo.descricao,
                        valor_centavos=aditivo.valor_centavos,
                        estado=aditivo.estado.value,
                    ),  # fmt: skip
                    cobranca=saida_cobranca,
                )
            aditivo = servico.recusar_aditivo(contexto, pedido, aditivo_id)
        except ErroFluxo as erro:
            raise HTTPException(erro.status, str(erro)) from erro
        except ErroProvedor as erro:
            raise _recusa_do_provedor(erro, meio) from erro
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
    if aprovar:
        _avisar_aditivo_aprovado(request, contexto, pedido, aditivo_id)
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
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
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
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AditivoDecididoOut:
    return _decidir_aditivo(
        request, contexto, usuario, contrato_id, aditivo_id, False, MeioPagamento.PIX
    )


# --- Nota de material -------------------------------------------------------------------


def _caminho_da_foto_valido(caminho: str) -> bool:
    partes = caminho.split("/")
    return not ("://" in caminho or ".." in partes or caminho.startswith("/") or "" in partes)


def _foto_da_nota(request: Request, corpo: NotaMaterialIn, pedido: Pedido, usuario: Usuario) -> str:
    """Caminho da foto: o `midia_id` do upload (conferido) ou o caminho que o app mandou."""
    if corpo.midia_id is not None:
        servico = getattr(request.app.state, "servico_uploads", None)
        if servico is None:
            raise HTTPException(503, "O envio de arquivos ainda não foi ligado.")
        midia = servico.repo.midia(corpo.midia_id)
        if (
            midia is None
            or midia.pedido_id != pedido.id
            or midia.enviada_por != usuario.id
            or midia.finalidade != "nota_material"
        ):
            raise HTTPException(422, "A foto da nota não foi enviada ou não é deste pedido.")
        return midia.storage_path
    caminho = (corpo.foto_storage_path or "").lstrip("/")
    if not _caminho_da_foto_valido(caminho):
        raise HTTPException(422, "O caminho da foto não é válido.")
    return caminho


def _nota_out(nota: NotaMaterial, servico_uploads: object | None = None) -> NotaMaterialOut:
    foto_url: str | None = None
    if servico_uploads is not None and nota.foto_storage_path:
        try:
            foto_url = servico_uploads.armazenamento.url_leitura(  # type: ignore[attr-defined]
                "pedido-midias", nota.foto_storage_path, 300
            )
        except Exception:  # noqa: BLE001 - falha no storage não derruba a nota
            foto_url = None
    return NotaMaterialOut(
        id=nota.id,
        contrato_id=nota.pedido_id,
        itens=[
            ItemNotaOut(descricao=d, quantidade=q, valor_unitario_centavos=u, total_centavos=t)
            for d, q, u, t in nota.itens
        ],  # fmt: skip
        total_centavos=nota.total_centavos,
        enviada_em=nota.enviada_em,
        foto_url=foto_url,
    )


def _recusa_do_provedor(erro: ErroProvedor, meio: MeioPagamento) -> HTTPException:
    """O parceiro recusou a cobrança (ex.: Pix desligado na conta): 502 claro, não 500 mudo."""
    log.warning("cobrança recusada pelo provedor (%s): %s", meio.value, erro)
    if meio is MeioPagamento.PIX:
        return HTTPException(
            502, "Não foi possível gerar o Pix agora. Tente de novo ou pague com cartão."
        )
    return HTTPException(502, "Não foi possível processar o pagamento agora. Tente de novo.")


def _cupom_ja_reservado(
    contexto: Contexto, servico: Any, usuario_id: str, pedido_id: str, codigo: str
) -> bool:
    """Cobrança com cupom pendente reserva o uso: respeita `limite_por_usuario` já na criação."""
    limite = limite_por_usuario_do_cupom(contexto, codigo)
    if limite is None:
        return False
    pendentes = 0
    for outro in contexto.pedidos.listar_do_usuario(usuario_id, True, limite=200):
        if outro.id == pedido_id:
            continue
        pendentes += sum(
            1
            for c in servico.cobrancas.do_pedido(outro.id)
            if c.status is EstadoCobranca.AGUARDANDO and c.cupom_codigo == codigo
        )
    return pendentes + usos_do_usuario_do_cupom(contexto, codigo, usuario_id) >= limite


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
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> NotaMaterialOut:
    pedido, contrato = _contrato_do_usuario(contexto, contrato_id, usuario)
    if contrato.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional contratado neste pedido envia nota.")
    if pedido.estado is not Estado.EM_ANDAMENTO:
        raise HTTPException(409, "Só dá para enviar nota com o serviço em andamento.")
    foto = _foto_da_nota(request, corpo, pedido, usuario)
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
    if total_nota > TETO_NOTA_MATERIAL_CENTAVOS:
        raise HTTPException(422, "O total da nota é alto demais.")
    agora = contexto.agora()
    with _TRAVA_NOTA_MATERIAL:
        for antiga in contexto.notas_material.do_pedido(pedido.id):
            if (
                antiga.profissional_id == usuario.id
                and antiga.foto_storage_path == foto
                and tuple(antiga.itens) == tuple(linhas)
                and timedelta(0) <= agora - antiga.enviada_em < JANELA_NOTA_DUPLICADA
            ):
                raise HTTPException(409, "Esta nota já foi enviada.")
        nota = contexto.notas_material.registrar(
            NotaMaterial("", pedido.id, usuario.id, foto, tuple(linhas), total_nota, agora)
        )
    avisar_evento(
        request, contexto, Evento.NOTA_MATERIAL, pedido.cliente_id,
        pedido_id=pedido.id, chave=f"nota-material:{nota.id}",
    )  # fmt: skip
    return _nota_out(nota, getattr(request.app.state, "servico_uploads", None))


@router.get(
    "/contratos/{contrato_id}/notas-material",
    response_model=list[NotaMaterialOut],
    summary="Notas de material do contrato",
)
def listar_notas_material(
    contrato_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[NotaMaterialOut]:
    pedido, _ = _contrato_do_usuario(contexto, contrato_id, usuario)
    uploads = getattr(request.app.state, "servico_uploads", None)
    return [_nota_out(n, uploads) for n in contexto.notas_material.do_pedido(pedido.id)]


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
    request: Request,
    resposta: Response,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AvaliacaoOut:
    return rotas_app.avaliar(contrato_id, corpo, request, resposta, usuario, contexto)


# --- Contraproposta de valor e prazo ------------------------------------------------------
#
# O cliente pode propor outro valor e/ou prazo de execução em dias; o profissional aceita
# (cria uma nova versão do orçamento mantendo as horas originais) ou envia uma nova proposta
# diretamente no chat. A negociação fica na conversa e cada nova proposta traz ação de aceite.

MARCA_CONTRAPROPOSTA = "[contraproposta:"
MARCA_PROPOSTA = "[proposta:"


def _reais(centavos: int) -> str:
    inteiro = f"{centavos // 100:,}".replace(",", ".")
    return f"R$ {inteiro},{centavos % 100:02d}"


def _rotulo_dias(dias: int | None) -> str:
    if dias is None:
        return ""
    return "1 dia" if dias == 1 else f"{dias} dias"


class ContrapropostaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor_centavos: StrictInt | None = Field(
        default=None, gt=0, le=TETO_CENTAVOS, description="O valor que o cliente propõe."
    )
    prazo_execucao_dias: StrictInt | None = Field(
        default=None, ge=1, le=365, description="O prazo de execução em dias proposto."
    )
    mensagem: str | None = Field(default=None, max_length=500)


class ContrapropostaOut(BaseModel):
    mensagem_id: int
    valor_centavos: int
    orcamento_id: str
    prazo_execucao_dias: int | None = None


class AceiteContrapropostaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor_centavos: StrictInt = Field(gt=0, le=TETO_CENTAVOS)
    prazo_execucao_dias: StrictInt | None = Field(default=None, ge=1, le=365)


class AceiteContrapropostaOut(BaseModel):
    orcamento_id: str
    valor_centavos: int
    versao: int | None = None
    prazo_execucao_dias: int | None = None


class NovaPropostaProfissionalIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    valor_centavos: StrictInt = Field(gt=0, le=TETO_CENTAVOS)
    prazo_execucao_dias: StrictInt | None = Field(default=None, ge=1, le=365)
    mensagem: str | None = Field(default=None, max_length=500)


def _orcamento_do_pedido(contexto: Contexto, pedido: Pedido, orcamento_id: str):  # type: ignore[no-untyped-def]
    detalhe = contexto.orcamentos.detalhe(orcamento_id)
    if detalhe is None or detalhe.pedido_id != pedido.id:
        raise HTTPException(404, "Orçamento não encontrado.")
    if detalhe.status != "enviado":
        raise HTTPException(409, "Este orçamento foi substituído por uma versão mais nova.")
    return detalhe


def _itens_preservando_horas(detalhe, valor_centavos: int) -> list[ItemOrcamento]:  # type: ignore[no-untyped-def]
    itens_novos = [
        ItemOrcamento(
            tipo="outro",
            descricao="Valor combinado na contraproposta",
            quantidade=Decimal(1),
            valor_unitario_centavos=valor_centavos,
        )
    ]
    # O cliente continua vendo as horas: itens de valor zero (o preço já está no combinado).
    desloc = somar_horas(detalhe.itens, "deslocamento")
    trab = somar_horas(detalhe.itens, "horas")
    if desloc is not None and desloc > 0:
        itens_novos.append(
            ItemOrcamento(
                tipo="deslocamento",
                descricao="Horas de deslocamento",
                quantidade=desloc,
                valor_unitario_centavos=0,
            )
        )
    if trab is not None and trab > 0:
        itens_novos.append(
            ItemOrcamento(
                tipo="horas",
                descricao="Horas trabalhadas",
                quantidade=trab,
                valor_unitario_centavos=0,
            )
        )
    return itens_novos


def _publicar_nova_versao_orcamento(
    *,
    request: Request,
    contexto: Contexto,
    pedido: Pedido,
    detalhe,  # type: ignore[no-untyped-def]
    profissional_id: str,
    valor_centavos: int,
    prazo_execucao_dias: int | None,
    texto_aviso: str,
) -> AceiteContrapropostaOut:
    prazo_final = (
        prazo_execucao_dias if prazo_execucao_dias is not None else detalhe.prazo_execucao_dias
    )
    novo_id = contexto.orcamentos.enviar(
        pedido_id=pedido.id,
        profissional_id=profissional_id,
        itens=_itens_preservando_horas(detalhe, valor_centavos),
        agora=contexto.agora(),
        prazo_execucao_dias=prazo_final,
        validade_ate=detalhe.validade_ate,
        garantia_dias=detalhe.garantia_dias,
        fora_do_escopo=detalhe.fora_do_escopo,
        observacoes=detalhe.observacoes,
    )
    conversa = contexto.conversas.abrir(pedido.id, profissional_id)
    dias_sufixo = f":{prazo_final}" if prazo_final is not None else ""
    texto_chat = f"{MARCA_PROPOSTA}{novo_id}:{valor_centavos}{dias_sufixo}] {texto_aviso}"
    aviso_id = contexto.conversas.enviar(conversa, profissional_id, texto_chat)
    avisar_mensagem_nova(
        request,
        contexto,
        conversa_id=conversa,
        pedido_id=pedido.id,
        autor_id=profissional_id,
        destinatario_id=pedido.cliente_id,
        mensagem_id=aviso_id,
    )
    avisar_orcamento_recebido(
        request,
        contexto,
        pedido_id=pedido.id,
        cliente_id=pedido.cliente_id,
        orcamento_id=novo_id,
    )
    novo = contexto.orcamentos.detalhe(novo_id)
    return AceiteContrapropostaOut(
        orcamento_id=novo_id,
        valor_centavos=valor_centavos,
        versao=novo.versao if novo else None,
        prazo_execucao_dias=prazo_final,
    )


@router.post(
    "/pedidos/{pedido_id}/orcamentos/{orcamento_id}/contraproposta",
    response_model=ContrapropostaOut,
    status_code=201,
    summary="Cliente propõe novo valor e/ou prazo em dias para o orçamento",
    description=(
        "Só o cliente dono do pedido, enquanto o pedido ainda recebe orçamentos. O valor não pode "
        "ultrapassar o orçamento atual e ao menos valor ou prazo em dias precisa mudar."
    ),
)
def contraproposta(
    pedido_id: str,
    orcamento_id: str,
    corpo: ContrapropostaIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ContrapropostaOut:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.cliente_id != usuario.id:
        raise HTTPException(404, "Pedido não encontrado.")
    if pedido.estado not in (Estado.ABERTO, Estado.RESERVADO):
        raise HTTPException(409, "Este pedido já não aceita contraproposta.")
    detalhe = _orcamento_do_pedido(contexto, pedido, orcamento_id)
    valor = corpo.valor_centavos if corpo.valor_centavos is not None else detalhe.valor_centavos
    if valor > detalhe.valor_centavos:
        raise HTTPException(
            422, f"A contraproposta não pode passar de {_reais(detalhe.valor_centavos)}."
        )
    mudou_valor = valor < detalhe.valor_centavos
    mudou_dias = (
        corpo.prazo_execucao_dias is not None
        and corpo.prazo_execucao_dias != detalhe.prazo_execucao_dias
    )
    if not (mudou_valor or mudou_dias):
        raise HTTPException(
            422,
            f"A contraproposta precisa ser menor que {_reais(detalhe.valor_centavos)} "
            "ou propor outro prazo em dias.",
        )
    extra = ""
    if corpo.mensagem:
        extra = " " + limpar_texto(corpo.mensagem, "mensagem", 500, obter_config_seguranca())
    dias_marca = f":{corpo.prazo_execucao_dias}" if corpo.prazo_execucao_dias is not None else ""
    dias_texto = (
        f" para executar em {_rotulo_dias(corpo.prazo_execucao_dias)}"
        if corpo.prazo_execucao_dias is not None
        else ""
    )
    texto = (
        f"{MARCA_CONTRAPROPOSTA}{orcamento_id}:{valor}{dias_marca}] "
        f"Contraproposta de {_reais(valor)}{dias_texto} "
        f"(o orçamento atual é {_reais(detalhe.valor_centavos)}).{extra}"
    )
    conversa = contexto.conversas.abrir(pedido.id, detalhe.profissional_id)
    mensagem_id = contexto.conversas.enviar(conversa, usuario.id, texto)
    avisar_mensagem_nova(
        request,
        contexto,
        conversa_id=conversa,
        pedido_id=pedido.id,
        autor_id=usuario.id,
        destinatario_id=detalhe.profissional_id,
        mensagem_id=mensagem_id,
    )
    return ContrapropostaOut(
        mensagem_id=mensagem_id,
        valor_centavos=valor,
        orcamento_id=orcamento_id,
        prazo_execucao_dias=corpo.prazo_execucao_dias,
    )


@router.post(
    "/pedidos/{pedido_id}/orcamentos/{orcamento_id}/contraproposta/aceitar",
    response_model=AceiteContrapropostaOut,
    status_code=201,
    summary="Profissional aceita a contraproposta e atualiza o orçamento",
    description=(
        "Só o autor do orçamento. Confere a contraproposta na conversa e cria uma nova versão "
        "do orçamento com o valor e prazo combinados, mantendo garantia e fora do escopo."
    ),
)
def aceitar_contraproposta(
    pedido_id: str,
    orcamento_id: str,
    corpo: AceiteContrapropostaIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AceiteContrapropostaOut:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if pedido.estado is not Estado.ABERTO:
        raise HTTPException(409, "Este pedido já não recebe mudança no orçamento.")
    detalhe = _orcamento_do_pedido(contexto, pedido, orcamento_id)
    if detalhe.profissional_id != usuario.id:
        raise HTTPException(404, "Orçamento não encontrado.")
    conversa = contexto.conversas.abrir(pedido.id, usuario.id)
    dias_marca = f":{corpo.prazo_execucao_dias}" if corpo.prazo_execucao_dias is not None else ""
    marca_exata = f"{MARCA_CONTRAPROPOSTA}{orcamento_id}:{corpo.valor_centavos}{dias_marca}]"
    houve = any(
        m.autor_id == pedido.cliente_id and m.texto.startswith(marca_exata)
        for m in contexto.conversas.listar(conversa)
    )
    if not houve:
        raise HTTPException(422, "O cliente não fez essa contraproposta.")
    mudou_dias = (
        corpo.prazo_execucao_dias is not None
        and corpo.prazo_execucao_dias != detalhe.prazo_execucao_dias
    )
    if corpo.valor_centavos > detalhe.valor_centavos or (
        corpo.valor_centavos == detalhe.valor_centavos and not mudou_dias
    ):
        raise HTTPException(409, "O orçamento já está nesse valor ou abaixo.")
    prazo_final = (
        corpo.prazo_execucao_dias
        if corpo.prazo_execucao_dias is not None
        else detalhe.prazo_execucao_dias
    )
    prazo_txt = f" em {_rotulo_dias(prazo_final)}" if prazo_final is not None else ""
    return _publicar_nova_versao_orcamento(
        request=request,
        contexto=contexto,
        pedido=pedido,
        detalhe=detalhe,
        profissional_id=usuario.id,
        valor_centavos=corpo.valor_centavos,
        prazo_execucao_dias=prazo_final,
        texto_aviso=(
            f"Contraproposta aceita. Novo orçamento de {_reais(corpo.valor_centavos)}{prazo_txt}."
        ),
    )


@router.post(
    "/pedidos/{pedido_id}/orcamentos/{orcamento_id}/propor",
    response_model=AceiteContrapropostaOut,
    status_code=201,
    summary="Profissional envia nova proposta de valor/dias pelo chat",
    description=(
        "Só o profissional autor do orçamento enquanto o pedido está aberto. Cria uma nova "
        "versão do orçamento com valor e/ou dias ajustados e coloca o cartão de aceite no chat."
    ),
)
def propor_nova_condicao(
    pedido_id: str,
    orcamento_id: str,
    corpo: NovaPropostaProfissionalIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AceiteContrapropostaOut:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if pedido.estado is not Estado.ABERTO:
        raise HTTPException(409, "Este pedido já não recebe mudança no orçamento.")
    detalhe = _orcamento_do_pedido(contexto, pedido, orcamento_id)
    if detalhe.profissional_id != usuario.id:
        raise HTTPException(404, "Orçamento não encontrado.")
    prazo_final = (
        corpo.prazo_execucao_dias
        if corpo.prazo_execucao_dias is not None
        else detalhe.prazo_execucao_dias
    )
    prazo_txt = f" em {_rotulo_dias(prazo_final)}" if prazo_final is not None else ""
    extra = ""
    if corpo.mensagem:
        extra = " " + limpar_texto(corpo.mensagem, "mensagem", 500, obter_config_seguranca())
    return _publicar_nova_versao_orcamento(
        request=request,
        contexto=contexto,
        pedido=pedido,
        detalhe=detalhe,
        profissional_id=usuario.id,
        valor_centavos=corpo.valor_centavos,
        prazo_execucao_dias=prazo_final,
        texto_aviso=(f"Nova proposta de {_reais(corpo.valor_centavos)}{prazo_txt}.{extra}"),
    )


# --- Pedidos abertos e recusa -----------------------------------------------------------


class OrdemPedidos(StrEnum):
    RECENTES = "recentes"
    ANTIGOS = "antigos"
    URGENTES = "urgentes"
    MAIOR_VALOR = "maior_valor"
    MENOR_VALOR = "menor_valor"
    PROXIMOS = "proximos"


def _distancia_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distância em linha reta (haversine), em km."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = (
        math.sin((p2 - p1) / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lng2 - lng1) / 2) ** 2
    )
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def _eh_convidado_do_pedido(
    contexto: Contexto | None, p: PedidoAberto, usuario_id: str | None
) -> bool:
    if p.convidado:
        return True
    if contexto is None or not usuario_id:
        return False
    convidados = contexto.extras.get("pedidos_convidados", {})
    if isinstance(convidados, dict) and convidados.get(p.id) == usuario_id:
        return True
    dados = contexto.pedidos.dados_do_pedido(p.id)
    return bool(dados is not None and dados.profissional_convidado_id == usuario_id)


def _saida_aberto(
    p: PedidoAberto,
    lat: float | None,
    lng: float | None,
    contexto: Contexto | None = None,
    *,
    usuario_id: str | None = None,
    categorias: Mapping[str, str] | None = None,
) -> PedidoAbertoOut:
    km = None
    # MAP-1: mesmo para pedido já salvo, o servidor devolve só a grade de ~500 m (nunca o ponto
    # exato) e o remoto nunca devolve ponto. A distância usa o ponto já encaixado.
    remoto = p.modalidade == "remoto"
    ponto_lat = None if remoto else na_grade(p.local_aprox_lat)
    ponto_lng = None if remoto else na_grade(p.local_aprox_lng)
    if lat is not None and lng is not None and ponto_lat is not None and ponto_lng is not None:
        km = round(_distancia_km(lat, lng, ponto_lat, ponto_lng), 1)
    nome = None
    if contexto is not None and p.cliente_id:
        detalhe = contexto.usuarios.detalhe(p.cliente_id)
        partes = (detalhe.nome or "").split() if detalhe else []
        if partes:
            nome = partes[0] if len(partes) == 1 else f"{partes[0]} {partes[-1][0]}."
    campos = {k: v for k, v in vars(p).items() if k != "convidado"}
    campos["local_aprox_lat"], campos["local_aprox_lng"] = ponto_lat, ponto_lng
    return PedidoAbertoOut(
        **campos,
        distancia_km=km,
        cliente_nome=nome,
        categoria_nome=(categorias or {}).get(str(p.categoria_id)) if p.categoria_id else None,
        ja_avaliou=False,
        convidado=_eh_convidado_do_pedido(contexto, p, usuario_id),
    )


def _teto_da_faixa(p: PedidoAberto) -> int:
    return p.faixa_preco_max_centavos if p.faixa_preco_max_centavos is not None else -1


def _profissional_disponivel_agora(request: Request | None, profissional_id: str) -> bool:
    if request is None:
        return False
    modulo = getattr(request.app.state, "modulo_profissional", None)
    if modulo is None:
        return False
    try:
        perfil = modulo.repo.obter(profissional_id)
    except Exception:  # noqa: BLE001 - estado secundário não bloqueia a rota
        return False
    return bool(perfil and perfil.disponivel_agora)


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
    request: Request,
    categoria_id: Annotated[str | None, Query()] = None,
    bairro: Annotated[str | None, Query(max_length=120)] = None,
    preco_min_centavos: Annotated[int | None, Query(ge=0, le=TETO_CENTAVOS)] = None,
    preco_max_centavos: Annotated[int | None, Query(ge=0, le=TETO_CENTAVOS)] = None,
    ordenar: OrdemPedidos = OrdemPedidos.RECENTES,
    limite: Annotated[int, Query(ge=1, le=100)] = 50,
    lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoAbertoOut]:
    if (
        preco_min_centavos is not None
        and preco_max_centavos is not None
        and preco_min_centavos > preco_max_centavos
    ):
        raise HTTPException(422, "O preço mínimo não pode passar do máximo.")
    categorias = nomes_de_categorias(request)  # catálogo lido na hora: vê categoria nova
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
    elif ordenar is OrdemPedidos.PROXIMOS and lat is not None and lng is not None:
        saida = [
            _saida_aberto(p, lat, lng, contexto, usuario_id=usuario.id, categorias=categorias)
            for p in itens
        ]
        saida.sort(key=lambda o: (not o.convidado, o.distancia_km is None, o.distancia_km or 0.0))
        return saida[:limite]
    elif _profissional_disponivel_agora(request, usuario.id):
        itens.sort(key=lambda p: (not p.urgente, -p.aberto_em.timestamp()))
    else:
        itens.sort(key=lambda p: p.aberto_em, reverse=True)
    saida = [
        _saida_aberto(p, lat, lng, contexto, usuario_id=usuario.id, categorias=categorias)
        for p in itens
    ]
    saida.sort(key=lambda o: not o.convidado)
    return saida[:limite]


class PedidoAbertoDetalheOut(PedidoAbertoOut):
    orcamentos_recebidos: int = Field(description="Quantos orçamentos enviados o pedido já tem.")
    ja_orcou: bool = Field(description="Se este profissional já enviou orçamento.")
    respostas: list[RespostaPedidoOut] = Field(
        default_factory=list, description="Respostas do cliente às perguntas da categoria."
    )
    fotos_urls: list[str] = Field(
        default_factory=list, description="URLs assinadas curtas das fotos do pedido."
    )


@router.get(
    "/profissional/pedidos-abertos/{pedido_id}",
    response_model=PedidoAbertoDetalheOut,
    summary="Detalhe de um pedido aberto (mesma visibilidade da lista)",
    description="Pedido que não está na lista dele (outra categoria, região, recusado ou já "
    "fechado) responde 404. Sem endereço exato.",
)
def pedido_aberto(
    pedido_id: str,
    request: Request,
    lat: Annotated[float | None, Query(ge=-90, le=90)] = None,
    lng: Annotated[float | None, Query(ge=-180, le=180)] = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoAbertoDetalheOut:
    recusados = {r.pedido_id for r in contexto.recusas.do_profissional(usuario.id)}
    achado = (
        None
        if pedido_id in recusados
        else pedido_visivel_ao_profissional(contexto, pedido_id, usuario.id)
    )
    if achado is None:
        raise HTTPException(404, "Pedido não encontrado.")
    orcamentos = contexto.orcamentos.do_pedido(achado.id)
    return PedidoAbertoDetalheOut(
        **_saida_aberto(
            achado,
            lat,
            lng,
            contexto,
            usuario_id=usuario.id,
            categorias=nomes_de_categorias(request),
        ).model_dump(),
        orcamentos_recebidos=len(orcamentos),
        ja_orcou=any(o.profissional_id == usuario.id for o in orcamentos),
        respostas=respostas_out(contexto, achado.id),
        fotos_urls=urls_fotos_do_pedido(request, achado.id),
    )


# --- Proposta e aceite de horário de visita no chat --------------------------------------

_REGEX_AGENDA = re.compile(r"^\[agenda:([^|\]]+)\|([^\]]+)\]")


class ProporAgendaIn(_Entrada):
    janela: JanelaIn
    justificativa: str = Field(default="", max_length=240)


class AceitarAgendaIn(_Entrada):
    mensagem_id: int | None = None
    janela: JanelaIn | None = None


def _formatar_janela_br(inicio: datetime, fim: datetime) -> str:
    return (
        f"{inicio.day:02d}/{inicio.month:02d} das "
        f"{inicio.hour:02d}:{inicio.minute:02d} às {fim.hour:02d}:{fim.minute:02d}"
    )


@router.post(
    "/pedidos/{pedido_id}/agenda/propor",
    response_model=rotas_app.MensagemOut,
    status_code=201,
    summary="Cliente ou profissional sugere um horário de visita no chat",
)
def propor_agenda(
    pedido_id: str,
    corpo: ProporAgendaIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> rotas_app.MensagemOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado not in (Estado.PAGO_E_RETIDO, Estado.AGENDADO):
        raise HTTPException(409, "Só dá para combinar ou remarcar a visita após o pagamento.")
    agora = contexto.agora()
    if corpo.janela.fim <= corpo.janela.inicio:
        raise HTTPException(422, "A janela de atendimento precisa terminar depois de começar.")
    if corpo.janela.inicio < agora:
        raise HTTPException(422, "A janela de atendimento não pode começar no passado.")
    profissional_id = pedido.profissional_id
    if not profissional_id:
        raise HTTPException(409, "Pedido sem profissional contratado.")
    conversa = contexto.conversas.abrir(pedido.id, profissional_id)
    resumo = _formatar_janela_br(corpo.janela.inicio, corpo.janela.fim)
    extra = ""
    if corpo.justificativa.strip():
        limpa = limpar_texto(corpo.justificativa, "justificativa", 240, obter_config_seguranca())
        extra = f" — {limpa}"
    texto = (
        f"[agenda:{corpo.janela.inicio.isoformat()}|{corpo.janela.fim.isoformat()}] "
        f"Sugestão de visita para {resumo}.{extra}"
    )
    nova = contexto.conversas.enviar(conversa, usuario.id, texto)
    destinatario = pedido.profissional_id if usuario.id == pedido.cliente_id else pedido.cliente_id
    avisar_mensagem_nova(
        request,
        contexto,
        conversa_id=conversa,
        pedido_id=pedido.id,
        autor_id=usuario.id,
        destinatario_id=destinatario,
        mensagem_id=nova,
    )
    msg = next(m for m in contexto.conversas.listar(conversa) if m.id == nova)
    return rotas_app.MensagemOut(
        id=msg.id,
        autor_id=msg.autor_id,
        minha=msg.autor_id == usuario.id,
        texto=msg.texto,
        mascarada=msg.mascarada,
        enviada_em=msg.enviada_em,
        lida_em=msg.lida_em,
        entregue_em=msg.entregue_em or msg.lida_em,
    )


@router.post(
    "/pedidos/{pedido_id}/agenda/aceitar",
    response_model=PedidoOut,
    summary="Aceitar sugestão de visita (confirma agenda ou remarca)",
)
def aceitar_agenda(
    pedido_id: str,
    corpo: AceitarAgendaIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado not in (Estado.PAGO_E_RETIDO, Estado.AGENDADO):
        raise HTTPException(409, "O pedido não está pronto para agendamento ou remarcação.")
    profissional_id = pedido.profissional_id
    if not profissional_id:
        raise HTTPException(409, "Pedido sem profissional contratado.")
    conversa = contexto.conversas.abrir(pedido.id, profissional_id)

    inicio: datetime | None = None
    fim: datetime | None = None
    if corpo.mensagem_id is not None:
        mensagens = contexto.conversas.listar(conversa)
        msg = next((m for m in mensagens if m.id == corpo.mensagem_id), None)
        if msg is None:
            raise HTTPException(404, "Sugestão de horário não encontrada nesta conversa.")
        if msg.autor_id == usuario.id:
            raise HTTPException(422, "Aguarde a outra parte confirmar o horário sugerido.")
        match = _REGEX_AGENDA.match(msg.texto)
        if match is None:
            raise HTTPException(422, "Esta mensagem não contém uma sugestão de horário.")
        inicio = datetime.fromisoformat(match.group(1).replace("Z", "+00:00"))
        fim = datetime.fromisoformat(match.group(2).replace("Z", "+00:00"))
    elif corpo.janela is not None:
        inicio = corpo.janela.inicio
        fim = corpo.janela.fim
    else:
        raise HTTPException(422, "Informe a mensagem ou a janela de horário.")

    janela = Janela(inicio, fim)
    agora = contexto.agora()
    prazos = contexto.config.carregar().prazos_pedido
    outra_parte = profissional_id if usuario.id == pedido.cliente_id else pedido.cliente_id
    if pedido.estado is Estado.PAGO_E_RETIDO:
        ator_agendar = Ator(Papel.PROFISSIONAL, profissional_id)
        transicao = pedidos_estados.transicionar(
            pedido,
            Acao.CONFIRMAR_AGENDA,
            ator_agendar,
            agora,
            ProvaAgenda(janela),
            prazos,
        )
    else:
        transicao = pedidos_estados.transicionar(
            pedido,
            Acao.REMARCAR,
            ator_de(usuario, pedido),
            agora,
            ProvaRemarcacao(janela, outra_parte),
            prazos,
        )

    with contexto.transacao():
        gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
        for gancho in contexto.apos_transicao:
            gancho(pedido, gravado, transicao.evento.acao, contexto)

    msg_conf = f"Visita confirmada para {_formatar_janela_br(inicio, fim)}."
    aviso_id = contexto.conversas.enviar(conversa, usuario.id, msg_conf)
    avisar_mensagem_nova(
        request,
        contexto,
        conversa_id=conversa,
        pedido_id=pedido.id,
        autor_id=usuario.id,
        destinatario_id=outra_parte,
        mensagem_id=aviso_id,
    )
    return pedido_out(gravado, usuario)


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
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> RecusaOut:
    if usuario.papel is not PapelUsuario.PROFISSIONAL:
        # Não revela que o pedido existe: só o cliente dono vê o 403 de "papel errado".
        dono = contexto.pedidos.obter(pedido_id)
        if dono is None or dono.cliente_id != usuario.id:
            raise HTTPException(404, "Pedido não encontrado.")
        exigir_papel(PapelUsuario.PROFISSIONAL)(usuario, contexto)  # levanta o 403 de sempre
    visivel = pedido_visivel_ao_profissional(contexto, pedido_id, usuario.id) is not None
    ja_recusou = any(r.pedido_id == pedido_id for r in contexto.recusas.do_profissional(usuario.id))
    if not (visivel or ja_recusou):
        raise HTTPException(404, "Pedido não encontrado.")
    motivo = limpar_texto(corpo.motivo, "motivo", 500, obter_config_seguranca())
    contexto.recusas.recusar(RecusaPedido(pedido_id, usuario.id, motivo, contexto.agora()))
    return RecusaOut(pedido_id=pedido_id)


# --- Perfil -----------------------------------------------------------------------------


def _perfil_out(contexto: Contexto, usuario: Usuario, request: Request | None = None) -> PerfilOut:
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
    disponivel_agora = _profissional_disponivel_agora(request, usuario.id) if tem_perfil else False
    exclusao_agendada_em = None
    if request is not None:
        fabrica = getattr(request.app.state, "lgpd_fabrica", None)
        if fabrica is not None:
            try:
                servico_lgpd = fabrica(request.app)
                if servico_lgpd is not None:
                    exclusao_agendada_em = servico_lgpd.exclusao_agendada_em(usuario.id)
            except Exception:  # noqa: BLE001 - falha no módulo LGPD não derruba /me
                exclusao_agendada_em = None
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
        disponivel_agora=disponivel_agora,
        status_verificacao=contexto.usuarios.status_verificacao(usuario.id) if tem_perfil else None,
        cpf_cadastrado=contexto.usuarios.tem_cpf(usuario.id),
        exclusao_agendada_em=exclusao_agendada_em,
    )


@router.get("/me", response_model=PerfilOut, summary="Meu perfil")
def meu_perfil(
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PerfilOut:
    return _perfil_out(contexto, usuario, request)


@router.patch("/me", response_model=PerfilOut, summary="Atualizar meu perfil (nome)")
def atualizar_perfil(
    corpo: AtualizarPerfilIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> PerfilOut:
    nome = nome_de_exibicao(corpo.nome)
    contexto.usuarios.garantir(usuario.id, nome)
    contexto.usuarios.atualizar_nome(usuario.id, nome)
    return _perfil_out(contexto, usuario, request)


def registrar_rotas(app: FastAPI) -> FastAPI:
    app.include_router(router)
    return app
