"""Tradução do JSON de evento no formato do Stripe para `EventoProvedor` (compartilhado)."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from trato.pagamentos.provedor.base import EventoProvedor, TipoEvento

TIPOS_STRIPE: dict[str, TipoEvento] = {
    "payment_intent.succeeded": TipoEvento.PAGAMENTO_CONFIRMADO,
    "payment_intent.payment_failed": TipoEvento.PAGAMENTO_FALHOU,
    "charge.refunded": TipoEvento.ESTORNO_CONFIRMADO,
    # Liquidação ao profissional: o evento real depende do modelo de contas (P7).
    "payout.paid": TipoEvento.LIQUIDACAO,
    "transfer.paid": TipoEvento.LIQUIDACAO,
}


def _inteiro(valor: Any) -> int | None:
    return valor if isinstance(valor, int) and not isinstance(valor, bool) else None


def interpretar_evento_stripe(payload: Mapping[str, Any]) -> EventoProvedor | None:
    tipo = TIPOS_STRIPE.get(str(payload.get("type")))
    evento_id = payload.get("id")
    dados = payload.get("data")
    objeto = dados.get("object") if isinstance(dados, dict) else None
    if tipo is None or not isinstance(evento_id, str) or not isinstance(objeto, dict):
        return None
    metadados = {str(k): str(v) for k, v in (objeto.get("metadata") or {}).items()}
    if tipo is TipoEvento.ESTORNO_CONFIRMADO:
        cobranca_id = objeto.get("payment_intent")
        valor = _inteiro(objeto.get("amount_refunded"))
    elif tipo is TipoEvento.LIQUIDACAO:
        cobranca_id = metadados.get("cobranca_id")
        valor = _inteiro(objeto.get("amount"))
    else:
        cobranca_id = objeto.get("id")
        # Pago é o valor RECEBIDO (pode ser menor que o pedido); sem ele, o valor da cobrança.
        valor = _inteiro(objeto.get("amount_received", objeto.get("amount")))
    return EventoProvedor(
        id=evento_id,
        tipo=tipo,
        cobranca_id=cobranca_id if isinstance(cobranca_id, str) else None,
        valor_centavos=valor,
        metadados=metadados,
        pedido_id=metadados.get("pedido_id") or objeto.get("transfer_group"),
        bruto=payload,
        objeto_id=objeto.get("id") if isinstance(objeto.get("id"), str) else None,
    )
