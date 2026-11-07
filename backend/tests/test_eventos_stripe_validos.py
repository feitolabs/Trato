"""Os tipos de evento que o Trato assina no Stripe têm de existir de verdade (o CLI recusa os inventados)."""

from trato.pagamentos.provedor.base import TipoEvento
from trato.pagamentos.provedor.stripe_formato import TIPOS_STRIPE, interpretar_evento_stripe

# Nomes reais da documentação do Stripe para estes fluxos.
EVENTOS_REAIS = {
    "payment_intent.succeeded",
    "payment_intent.payment_failed",
    "charge.refunded",
    "payout.paid",
    "charge.dispute.created",
    "charge.dispute.updated",
    "charge.dispute.closed",
    "transfer.reversed",
    "payout.failed",
}


def test_so_eventos_que_existem_no_stripe():
    assert set(TIPOS_STRIPE) == EVENTOS_REAIS
    assert "transfer.paid" not in TIPOS_STRIPE


def test_liquidacao_vem_de_payout_paid():
    evento = interpretar_evento_stripe(
        {"id": "evt_1", "type": "payout.paid", "data": {"object": {"id": "po_1", "amount": 900}}}
    )
    assert evento is not None and evento.tipo is TipoEvento.LIQUIDACAO


def test_transfer_paid_e_ignorado():
    payload = {
        "id": "evt_2",
        "type": "transfer.paid",
        "data": {"object": {"id": "tr_1", "amount": 900}},
    }
    assert interpretar_evento_stripe(payload) is None
