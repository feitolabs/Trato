"""D13: nenhum pedido vira "pago" nem lança no ledger antes do webhook assinado."""

import hashlib
import hmac
import json

from conftest import AGORA, CLIENTE, PROFISSIONAL, SEGREDO_WEBHOOK, cab

from trato.financeiro.ledger import CUSTODIA
from trato.pedidos.estados import Estado

URL = "/v1/webhooks/stripe"


def assinar(corpo: bytes, segredo: str = SEGREDO_WEBHOOK) -> str:
    t = int(AGORA.timestamp())
    v1 = hmac.new(segredo.encode(), f"{t}.".encode() + corpo, hashlib.sha256).hexdigest()
    return f"t={t},v1={v1}"


def evento(id_="evt_1", tipo="payment_intent.succeeded", valor=100_000, pedido="ped-1") -> bytes:
    objeto = {"id": "pi_1", "amount": valor, "metadata": {"pedido_id": pedido}}
    return json.dumps({"id": id_, "type": tipo, "data": {"object": objeto}}).encode()


def enviar(amb, corpo: bytes, assinatura: str | None = None):
    return amb.cliente.post(
        URL, content=corpo, headers={"Stripe-Signature": assinatura or assinar(corpo)}
    )


def pedido(amb):
    return amb.contexto.pedidos.obter("ped-1")


def custodia(amb) -> int:
    return amb.contexto.ledger.saldo_da_conta(CUSTODIA, "ped-1")


def informar(amb):
    return amb.cliente.post("/v1/pedidos/ped-1/acoes/informar_pagamento", headers=cab("t-cliente"))


def test_aviso_do_cliente_nao_vira_pago_nem_lanca_no_ledger(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)

    r = informar(amb)

    assert r.status_code == 200
    assert r.json()["estado"] == "aguardando_confirmacao"
    assert r.json()["pagamento_confirmado"] is False
    assert pedido(amb).referencia_pagamento is None
    assert amb.contexto.ledger.lancamentos("ped-1") == ()


def test_so_o_sistema_confirma_pagamento_pela_api(amb):
    amb.semear_pedido(Estado.AGUARDANDO_CONFIRMACAO)

    for token in ("t-cliente", "t-prof", "t-equipe"):
        r = amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/confirmar_pagamento",
            headers=cab(token),
            json={"prova": {"referencia_pagamento": "pi_falso"}},
        )
        assert r.status_code in (400, 403, 422)
    assert pedido(amb).estado is Estado.AGUARDANDO_CONFIRMACAO


def test_webhook_assinado_confirma_e_lanca_a_cobranca(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    informar(amb)

    r = enviar(amb, evento())

    assert r.status_code == 200
    assert pedido(amb).estado is Estado.PAGO_E_RETIDO
    assert pedido(amb).referencia_pagamento == "pi_1"
    assert custodia(amb) == 100_000
    out = amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente")).json()
    assert out["pagamento_confirmado"] is True


def test_reenvio_duplicado_nao_lanca_duas_vezes(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    corpo = evento()

    primeiro = enviar(amb, corpo)
    segundo = enviar(amb, corpo)

    assert primeiro.json()["duplicado"] is False
    assert segundo.json()["duplicado"] is True
    assert custodia(amb) == 100_000
    assert len(amb.contexto.ledger.lancamentos("ped-1")) == 1


def test_outro_evento_do_mesmo_pagamento_nao_repete_o_efeito(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)

    enviar(amb, evento("evt_1"))
    enviar(amb, evento("evt_2"))

    assert custodia(amb) == 100_000
    assert len(amb.contexto.pedidos.eventos("ped-1")) == 1


def test_confirmacao_antes_do_aviso_do_cliente_vale(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)

    enviar(amb, evento())

    assert pedido(amb).estado is Estado.PAGO_E_RETIDO


def test_confirmacao_antes_do_aceite_do_orcamento_e_reenviada_depois(amb):
    amb.semear_pedido(Estado.ABERTO)
    corpo = evento()

    r = enviar(amb, corpo)

    assert r.status_code == 409
    assert pedido(amb).estado is Estado.ABERTO
    assert amb.contexto.ledger.lancamentos("ped-1") == ()
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    assert enviar(amb, corpo).status_code == 200
    assert pedido(amb).estado is Estado.PAGO_E_RETIDO


def test_recusa_depois_da_confirmacao_nao_desfaz_o_pago(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    enviar(amb, evento("evt_ok"))

    r = enviar(amb, evento("evt_falha", "payment_intent.payment_failed"))

    assert r.status_code == 200
    assert pedido(amb).estado is Estado.PAGO_E_RETIDO
    assert custodia(amb) == 100_000


def test_recusa_do_parceiro_volta_para_orcamento_aceito_sem_ledger(amb):
    amb.semear_pedido(Estado.AGUARDANDO_CONFIRMACAO)

    enviar(amb, evento("evt_falha", "payment_intent.payment_failed"))

    assert pedido(amb).estado is Estado.ORCAMENTO_ACEITO
    assert amb.contexto.ledger.lancamentos("ped-1") == ()


def test_assinatura_invalida_nao_confirma_nada(amb):
    amb.semear_pedido(Estado.AGUARDANDO_CONFIRMACAO)
    corpo = evento()

    for assinatura in (assinar(corpo, "segredo-errado-qualquer"), "t=1,v1=00", "lixo"):
        assert enviar(amb, corpo, assinatura).status_code == 400
    sem = amb.cliente.post(URL, content=corpo)
    assert sem.status_code == 400
    assert pedido(amb).estado is Estado.AGUARDANDO_CONFIRMACAO
    assert amb.contexto.ledger.lancamentos("ped-1") == ()


def test_valor_diferente_do_contrato_nao_vira_pago(amb):
    amb.semear_pedido(Estado.AGUARDANDO_CONFIRMACAO)

    r = enviar(amb, evento(valor=1))

    assert r.status_code == 200
    assert pedido(amb).estado is Estado.AGUARDANDO_CONFIRMACAO
    assert amb.contexto.ledger.lancamentos("ped-1") == ()


def test_pedido_de_outra_pessoa_nao_e_afetado(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)

    r = enviar(amb, evento(pedido="nao-existe"))

    assert r.status_code == 200
    assert pedido(amb).estado is Estado.ORCAMENTO_ACEITO
    assert CLIENTE.id and PROFISSIONAL.id
