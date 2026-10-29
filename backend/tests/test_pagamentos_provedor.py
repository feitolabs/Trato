import json

import pytest

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.provedor import (
    ErroProvedor,
    ProvedorFake,
    ProvedorStripeTeste,
    StatusCobranca,
    TipoEvento,
)
from trato.pagamentos.webhook import AssinaturaInvalida

CHAVE_TESTE = "sk_test_" + "x" * 12  # verificar: ignorar


def _criar(fake: ProvedorFake, chave="k1"):
    return fake.criar_cobranca(
        valor_centavos=5_000,
        meio=MeioPagamento.PIX,
        chave_idempotencia=chave,
        metadados={"pedido_id": "p1"},
    )


def test_fake_e_deterministico_e_idempotente():
    a, b = ProvedorFake(), ProvedorFake()
    assert _criar(a).id == _criar(b).id
    assert _criar(a) is _criar(a)
    assert _criar(a, "k2").id != _criar(a).id


def test_fake_valida_valor_e_estorno():
    fake = ProvedorFake()
    with pytest.raises(ErroProvedor):
        fake.criar_cobranca(
            valor_centavos=0, meio=MeioPagamento.PIX, chave_idempotencia="z", metadados={}
        )
    cobranca = _criar(fake)
    with pytest.raises(ErroProvedor):
        fake.estornar(cobranca.id, 100, "e1")  # ainda não paga
    fake.marcar_paga(cobranca.id)
    assert fake.consultar_cobranca(cobranca.id).status is StatusCobranca.PAGA
    assert fake.estornar(cobranca.id, 2_000, "e1") is fake.estornar(cobranca.id, 2_000, "e1")
    with pytest.raises(ErroProvedor):
        fake.estornar(cobranca.id, 4_000, "e2")  # só restam 3.000


def test_fake_assina_e_valida_webhook():
    fake = ProvedorFake()
    cobranca = _criar(fake)
    corpo, cabs = fake.evento_assinado(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca.id)
    evento = fake.validar_webhook(corpo, cabs["Stripe-Signature"], agora=1_793_275_200)
    assert evento.tipo is TipoEvento.PAGAMENTO_CONFIRMADO
    assert evento.pedido_id == "p1" and evento.valor_centavos == 5_000
    assert fake.evento_assinado(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca.id)[0] == corpo
    with pytest.raises(AssinaturaInvalida):
        fake.validar_webhook(corpo + b" ", cabs["Stripe-Signature"], agora=1_793_275_200)


def test_stripe_recusa_chave_de_producao_e_segredo_vazio():
    def nunca(*_):
        raise AssertionError("não deveria chamar a rede")

    with pytest.raises(ErroProvedor):
        ProvedorStripeTeste("sk_live_" + "x" * 12, "segredo", nunca)  # verificar: ignorar
    with pytest.raises(ErroProvedor):
        ProvedorStripeTeste(CHAVE_TESTE, "", nunca)


def test_stripe_monta_chamadas_e_le_respostas_simuladas():
    chamadas = []

    def transporte(metodo, caminho, campos, cabecalhos):
        chamadas.append((metodo, caminho, dict(campos), dict(cabecalhos)))
        if caminho == "/v1/payment_intents":
            return 200, {
                "id": "pi_1",
                "amount": 5_000,
                "status": "requires_action",
                "metadata": {"pedido_id": "p1"},
                "next_action": {"pix_display_qr_code": {"data": "000201pix"}},
            }
        if caminho == "/v1/refunds":
            return 200, {"id": "re_1", "amount": 2_000, "status": "succeeded"}
        if caminho == "/v1/payment_intents/pi_2":
            return 200, {
                "id": "pi_2",
                "amount": 100,
                "status": "requires_payment_method",
                "last_payment_error": {"code": "card_declined"},
            }
        return 402, {"error": {"message": "recusado"}}

    stripe = ProvedorStripeTeste(CHAVE_TESTE, "segredo-do-webhook", transporte)
    cobranca = stripe.criar_cobranca(
        valor_centavos=5_000,
        meio=MeioPagamento.PIX,
        chave_idempotencia="cob/p1/1",
        metadados={"pedido_id": "p1"},
    )
    assert cobranca.status is StatusCobranca.AGUARDANDO and cobranca.instrucao == "000201pix"
    _, _, campos, cabs = chamadas[0]
    assert campos["amount"] == "5000" and campos["metadata[pedido_id]"] == "p1"
    assert campos["payment_method_types[]"] == "pix" and cabs == {"Idempotency-Key": "cob/p1/1"}

    estorno = stripe.estornar("pi_1", 2_000, "est/1")
    assert estorno.confirmado and chamadas[1][2] == {"payment_intent": "pi_1", "amount": "2000"}
    assert stripe.consultar_cobranca("pi_2").status is StatusCobranca.FALHOU
    with pytest.raises(ErroProvedor, match="recusado"):
        stripe.consultar_cobranca("pi_x")
    with pytest.raises(ErroProvedor):
        stripe.criar_cobranca(
            valor_centavos=1,
            meio=MeioPagamento.CARTAO,
            chave_idempotencia="c",
            metadados={},
            parcelas=3,
        )


def test_stripe_valida_webhook_no_formato_do_stripe():
    stripe = ProvedorStripeTeste(CHAVE_TESTE, "segredo-do-webhook", lambda *_: (200, {}))
    corpo = json.dumps(
        {
            "id": "evt_1",
            "type": "charge.refunded",
            "data": {"object": {"id": "ch_1", "payment_intent": "pi_1", "amount_refunded": 700}},
        }
    ).encode()
    fake = ProvedorFake("segredo-do-webhook")
    cab = fake.assinar(corpo, 1_793_275_200)
    evento = stripe.validar_webhook(corpo, cab, agora=1_793_275_200)
    assert evento.tipo is TipoEvento.ESTORNO_CONFIRMADO
    assert (evento.cobranca_id, evento.valor_centavos) == ("pi_1", 700)
    with pytest.raises(AssinaturaInvalida):
        stripe.validar_webhook(
            corpo, fake.assinar(corpo, 1_793_275_200, "outro"), agora=1_793_275_200
        )
