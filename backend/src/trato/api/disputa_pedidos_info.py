"""Regras de pedido de informação adicional em disputas (Termos 8.4): prazo mínimo de 10 dias úteis
em Brasília com feriados e prorrogação 22.3 na leitura, validação do destinatário, encerramento sem
resposta após o prazo e aviso ao destinatário."""

from __future__ import annotations

import logging
from datetime import datetime, time
from typing import Any, Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field

from trato.api.indisponibilidade import APP, prazo_vigente
from trato.disputas.prazos import adicionar_dias_uteis
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.persistencia.disputa_pedidos_info import PedidoInformacao

log = logging.getLogger("trato.disputa_pedidos_info")
DIAS_MINIMO = 10  # Termos 8.4: mínimo 10 dias úteis em Brasília

StatusPedidoInfo = Literal["aguardando_resposta", "vencido", "respondido", "encerrado_sem_resposta"]


class PedidoInfoOut(BaseModel):
    id: str
    disputa_id: str
    pedido_id: str
    solicitante_id: str
    destinatario_papel: Literal["cliente", "profissional"]
    mensagem: str
    solicitado_em: datetime
    responder_ate: datetime = Field(description="Prazo em Brasília já com a prorrogação 22.3.")
    respondido_em: datetime | None
    resposta_texto: str | None
    encerrado_sem_resposta_em: datetime | None
    status: StatusPedidoInfo


class PedidoInfoAppOut(BaseModel):
    id: str
    disputa_id: str
    pedido_id: str
    destinatario_papel: Literal["cliente", "profissional"]
    mensagem: str
    solicitado_em: datetime
    responder_ate: datetime = Field(description="Prazo em Brasília já com a prorrogação 22.3.")
    respondido_em: datetime | None
    resposta_texto: str | None
    encerrado_sem_resposta_em: datetime | None
    status: StatusPedidoInfo


def saida_app(contexto: Any, item: PedidoInformacao, pedido_id: str) -> PedidoInfoAppOut:
    return PedidoInfoAppOut(
        id=item.id,
        disputa_id=item.disputa_id,
        pedido_id=pedido_id,
        destinatario_papel=item.destinatario_papel,  # type: ignore[arg-type]
        mensagem=item.mensagem,
        solicitado_em=item.solicitado_em,
        responder_ate=responder_ate_vigente(contexto, item),
        respondido_em=item.respondido_em,
        resposta_texto=item.resposta_texto,
        encerrado_sem_resposta_em=item.encerrado_sem_resposta_em,
        status=status_do_item(contexto, item),
    )


def exigir_tabela(contexto: Any) -> None:
    if not contexto.disputa_pedidos_info.disponivel():
        raise HTTPException(
            503, "Os pedidos de informação adicional da disputa ainda não estão disponíveis."
        )


def prazo_original(contexto: Any, solicitado_em: datetime) -> datetime:
    """Fim do 10º dia útil seguinte em Brasília (o dia da solicitação não conta)."""
    local = solicitado_em.astimezone(periodo.BRASILIA)
    ultimo = adicionar_dias_uteis(local, DIAS_MINIMO, contexto.config.carregar().disputas.feriados)
    return datetime.combine(ultimo.date(), time(23, 59, 59), periodo.BRASILIA)


def responder_ate_vigente(contexto: Any, item: PedidoInformacao) -> datetime:
    """Prazo com a prorrogação 22.3 (falha do app) calculada na leitura."""
    prorrogado = prazo_vigente(contexto, APP, item.solicitado_em, item.responder_ate)
    return prorrogado or item.responder_ate


def status_do_item(contexto: Any, item: PedidoInformacao) -> StatusPedidoInfo:
    if item.respondido_em is not None:
        return "respondido"
    if item.encerrado_sem_resposta_em is not None:
        return "encerrado_sem_resposta"
    if contexto.agora() > responder_ate_vigente(contexto, item):
        return "vencido"
    return "aguardando_resposta"


def saida(contexto: Any, item: PedidoInformacao, pedido_id: str) -> PedidoInfoOut:
    return PedidoInfoOut(
        id=item.id,
        disputa_id=item.disputa_id,
        pedido_id=pedido_id,
        solicitante_id=item.solicitante_id,
        destinatario_papel=item.destinatario_papel,  # type: ignore[arg-type]
        mensagem=item.mensagem,
        solicitado_em=item.solicitado_em,
        responder_ate=responder_ate_vigente(contexto, item),
        respondido_em=item.respondido_em,
        resposta_texto=item.resposta_texto,
        encerrado_sem_resposta_em=item.encerrado_sem_resposta_em,
        status=status_do_item(contexto, item),
    )


def resolver_disputa_e_pedido(contexto: Any, identificador: str) -> tuple[str, Any, Any]:
    achado = contexto.disputa_pedidos_info.resolver_disputa(identificador)
    if achado is None:
        raise HTTPException(404, "Disputa não encontrada.")
    disputa_id, pedido_id = achado
    disputa = contexto.disputas.obter(pedido_id)
    pedido = contexto.pedidos.obter(pedido_id)
    if disputa is None or pedido is None:
        raise HTTPException(404, "Disputa não encontrada.")
    return disputa_id, disputa, pedido


def notificar_solicitacao(
    contexto: Any,
    destinatario_id: str,
    pedido_id: str,
    item: PedidoInformacao,
) -> None:
    notificador = contexto.extras.get("notificador")
    if notificador is None:
        return
    try:
        ate = responder_ate_vigente(contexto, item).astimezone(periodo.BRASILIA)
        notificador.notificar(
            Evento.DISPUTA_PEDIDO_INFORMACAO,
            destinatario_id,
            chave=f"disputa-info:{item.id}",
            pedido_id=pedido_id,
            corpo=(
                "A equipe do Trato pediu informações adicionais na disputa do seu pedido. "
                f"Responda pelo aplicativo até {ate:%d/%m/%Y}."
            ),
        )
    except Exception:  # noqa: BLE001 - notificação não desfaz o pedido já gravado
        log.exception("Notificação do pedido de informação falhou (%s)", item.id)
