"""Financeiro do painel: contestações, alertas, consulta ao provedor (só leitura de dinheiro).

Nada aqui move dinheiro nem marca "pago": o espelho só muda pelo webhook assinado (D13). As rotas
mostram o que o provedor avisou e o que travou, para o financeiro agir.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.pedidos.estados import Estado

router = APIRouter(prefix="/v1/admin/financeiro", tags=["admin: financeiro"])

CHAVE_MINUTOS_PARADO = "alerta_pagamento_parado_minutos"
MINUTOS_PARADO_PADRAO = 30  # vale até a definição ser aprovada em Configurações
TIPOS_FALHA_REPASSE = ("transfer.reversed", "payout.failed")


# --- Modelos ------------------------------------------------------------------------------------


class ContestacaoOut(BaseModel):
    id: str
    pedido_id: str | None
    pedido_numero: int | None = None
    pedido_titulo: str | None = None
    cobranca_id: str | None
    valor_centavos: int
    motivo: str | None
    motivo_legivel: str
    status: str
    prazo_provas: datetime | None
    horas_para_prazo: int | None
    aberta_em: datetime
    encerrada_em: datetime | None
    repasse_liberado: bool


class PagamentoParadoOut(BaseModel):
    cobranca_id: str
    pedido_id: str
    pedido_numero: int | None = None
    valor_centavos: int
    meio: str
    criada_em: datetime
    minutos_parado: int
    cliente_avisou: bool  # o cliente disse no app que pagou e o webhook não veio


class EventoRevisaoOut(BaseModel):
    evento_id: str
    tipo: str
    recebido_em: datetime
    motivo: str
    pedido_id: str | None = None


class EstornoPendenteOut(BaseModel):
    chave: str
    pedido_id: str
    cobranca_id: str
    valor_centavos: int
    criada_em: datetime


class AlertasFinanceirosOut(BaseModel):
    minutos_pagamento_parado: int
    provedor_ligado: bool
    pagamentos_parados: list[PagamentoParadoOut]
    repasses_com_falha: list[EventoRevisaoOut]
    estornos_pendentes: list[EstornoPendenteOut]
    eventos_em_revisao: list[EventoRevisaoOut]
    contestacoes_em_aberto: int


class ConsultaCobrancaOut(BaseModel):
    cobranca_id: str
    status_no_provedor: str
    status_no_trato: str | None
    valor_centavos: int
    orientacao: str


# --- Apoio -------------------------------------------------------------------------------------


def servico_pagamento(request: Request) -> Any | None:
    """O serviço de pagamento ligado ao app (provedor + cobranças), ou `None` sem provedor."""
    return getattr(request.app.state, "servico_pagamento", None)


def _minutos_parado(admin: AdminContexto) -> int:
    vigente = admin.config.vigente()
    for parametro in vigente.parametros if vigente else ():
        if parametro.chave == CHAVE_MINUTOS_PARADO and parametro.valor:
            return int(parametro.valor)
    return MINUTOS_PARADO_PADRAO


def _contestacao_out(
    c: Contestacao, contexto: Contexto, rotulos: dict[str, tuple[int | None, str]]
) -> ContestacaoOut:
    agora = contexto.agora()
    horas = None
    if c.prazo_provas is not None and c.status.em_aberto:
        horas = int((c.prazo_provas - agora).total_seconds() // 3600)
    liberado = bool(c.pedido_id) and any(
        r.status == "liberado" for r in contexto.repasses.do_pedido(c.pedido_id or "")
    )
    numero, titulo = rotulos.get(c.pedido_id or "", (None, None))
    return ContestacaoOut(
        id=c.provedor_contestacao_id,
        pedido_id=c.pedido_id,
        pedido_numero=numero,
        pedido_titulo=titulo,
        cobranca_id=c.cobranca_id,
        valor_centavos=c.valor_centavos,
        motivo=c.motivo,
        motivo_legivel=c.motivo_legivel,
        status=c.status.value,
        prazo_provas=c.prazo_provas,
        horas_para_prazo=horas,
        aberta_em=c.aberta_em,
        encerrada_em=c.encerrada_em,
        repasse_liberado=liberado,
    )


def _pedido_do_evento(payload: dict[str, Any]) -> str | None:
    dados = payload.get("data")
    objeto = dados.get("object") if isinstance(dados, dict) else None
    meta = objeto.get("metadata") if isinstance(objeto, dict) else None
    valor = meta.get("pedido_id") if isinstance(meta, dict) else None
    return valor if isinstance(valor, str) else None


# --- Rotas -------------------------------------------------------------------------------------


@router.get("/contestacoes", response_model=list[ContestacaoOut], summary="Contestações de cartão")
def listar_contestacoes(
    status: str | None = Query(
        None, pattern="^(em_aberto|aberta|em_analise|ganha|perdida|encerrada)$"
    ),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> list[ContestacaoOut]:
    """Da mais urgente (prazo de provas mais perto) para a mais antiga."""
    todas = [
        c
        for c in contexto.contestacoes.listar()
        if status is None
        or (status == "em_aberto" and c.status.em_aberto)
        or c.status.value == status
    ]
    rotulos = admin.pedidos.rotulos([c.pedido_id for c in todas if c.pedido_id])
    saida = [_contestacao_out(c, contexto, rotulos) for c in todas]
    saida.sort(key=lambda c: (c.horas_para_prazo is None, c.horas_para_prazo or 0))
    return saida


@router.get(
    "/alertas", response_model=AlertasFinanceirosOut, summary="O que travou no dinheiro e pede ação"
)
def alertas(
    request: Request,
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> AlertasFinanceirosOut:
    agora = contexto.agora()
    minutos = _minutos_parado(admin)
    servico = servico_pagamento(request)
    parados: list[PagamentoParadoOut] = []
    pendentes: list[EstornoPendenteOut] = []
    if servico is not None:
        for c in servico.cobrancas.aguardando_desde_antes(agora - timedelta(minutes=minutos)):
            pedido = contexto.pedidos.obter(c.pedido_id)
            parados.append(
                PagamentoParadoOut(
                    cobranca_id=c.id,
                    pedido_id=c.pedido_id,
                    valor_centavos=c.valor_centavos,
                    meio=c.meio.value,
                    criada_em=c.criada_em,
                    minutos_parado=int((agora - c.criada_em).total_seconds() // 60),
                    cliente_avisou=pedido is not None
                    and pedido.estado is Estado.AGUARDANDO_CONFIRMACAO,
                )
            )
        # Quem o cliente já avisou que pagou vem primeiro; depois o mais antigo.
        parados.sort(key=lambda p: (not p.cliente_avisou, p.criada_em))
        pendentes = [
            EstornoPendenteOut(
                chave=o.chave,
                pedido_id=o.pedido_id,
                cobranca_id=o.cobranca_id,
                valor_centavos=o.valor_centavos,
                criada_em=o.criada_em,
            )
            for o in servico.ordens.pendentes()
        ]
    rotulos = admin.pedidos.rotulos([p.pedido_id for p in parados])
    for p in parados:
        p.pedido_numero = rotulos.get(p.pedido_id, (None, ""))[0]

    revisao = [
        EventoRevisaoOut(
            evento_id=e.evento_id,
            tipo=e.tipo,
            recebido_em=e.recebido_em,
            motivo=motivo.removeprefix("revisar: "),
            pedido_id=_pedido_do_evento(e.payload),
        )
        for e, motivo in contexto.eventos_webhook.em_revisao()
    ]
    revisao.sort(key=lambda e: e.recebido_em, reverse=True)
    em_aberto = sum(1 for c in contexto.contestacoes.listar() if c.status.em_aberto)
    return AlertasFinanceirosOut(
        minutos_pagamento_parado=minutos,
        provedor_ligado=servico is not None,
        pagamentos_parados=parados,
        repasses_com_falha=[e for e in revisao if e.tipo in TIPOS_FALHA_REPASSE],
        estornos_pendentes=pendentes,
        eventos_em_revisao=[e for e in revisao if e.tipo not in TIPOS_FALHA_REPASSE],
        contestacoes_em_aberto=em_aberto,
    )


@router.post(
    "/cobrancas/{cobranca_id}/consultar",
    response_model=ConsultaCobrancaOut,
    summary="Pergunta ao provedor como está a cobrança (não muda nada no Trato)",
)
def consultar_cobranca(
    cobranca_id: str,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.PAGAMENTOS_CONCILIAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> ConsultaCobrancaOut:
    servico = servico_pagamento(request)
    if servico is None:
        raise HTTPException(503, "Provedor de pagamento não configurado.")
    local = servico.cobrancas.obter(cobranca_id)
    if local is None:
        raise HTTPException(404, "Cobrança não encontrada.")
    try:
        remota = servico.provedor.consultar_cobranca(cobranca_id)
    except Exception as erro:  # noqa: BLE001 - qualquer falha do provedor vira 502 sem detalhe
        raise HTTPException(502, "O provedor não respondeu. Tente de novo em instantes.") from erro
    pago_la = remota.status.value == "paga"
    if pago_la and local.status.value != "paga":
        orientacao = (
            "O provedor já confirmou o pagamento, mas o aviso não chegou ao Trato. Reenvie o "
            "evento payment_intent.succeeded pelo painel do provedor: o Trato só marca pago "
            "pelo aviso assinado."
        )
    elif pago_la:
        orientacao = "Pago no provedor e no Trato. Nada a fazer."
    else:
        orientacao = "O provedor ainda não recebeu o pagamento. O cliente precisa concluir."
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="pagamento.consultado_no_provedor",
        entidade="pagamentos",
        depois={"cobranca_id": cobranca_id, "status_no_provedor": remota.status.value},
    )
    return ConsultaCobrancaOut(
        cobranca_id=cobranca_id,
        status_no_provedor=remota.status.value,
        status_no_trato=local.status.value,
        valor_centavos=remota.valor_centavos,
        orientacao=orientacao,
    )


__all__ = ["StatusContestacao", "router", "servico_pagamento"]
