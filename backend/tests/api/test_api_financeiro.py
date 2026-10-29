from conftest import cab

from trato.pedidos.estados import Estado


def test_saldo_do_pedido_vem_do_ledger(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    r = amb.cliente.get("/v1/pedidos/ped-1/saldo", headers=cab("t-cliente"))

    assert r.status_code == 200
    assert r.json() == {
        "pedido_id": "ped-1",
        "cliente_pagou_centavos": 100_000,
        "retido_centavos": 0,
        "a_liberar_centavos": 92_500,
        "liberado_centavos": 0,
        "taxa_trato_centavos": 7_500,
    }


def test_saldo_do_pedido_com_dinheiro_retido(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.semear_dinheiro(30_000)

    corpo = amb.cliente.get("/v1/pedidos/ped-1/saldo", headers=cab("t-equipe")).json()

    assert corpo["retido_centavos"] == 30_000


def test_saldo_do_pedido_nao_vaza_para_estranho(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)

    assert (
        amb.cliente.get("/v1/pedidos/ped-1/saldo", headers=cab("t-outro-cliente")).status_code
        == 404
    )
    assert amb.cliente.get("/v1/pedidos/ped-1/saldo").status_code == 401


def test_carteira_do_profissional(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    r = amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-prof"))

    assert r.json() == {"a_liberar_centavos": 92_500, "liberado_centavos": 0}
    assert amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-outro-prof")).json() == {
        "a_liberar_centavos": 0,
        "liberado_centavos": 0,
    }


def test_carteira_so_para_profissional(amb):
    assert (
        amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-cliente")).status_code == 403
    )
    assert amb.cliente.get("/v1/profissionais/me/saldo", headers=cab("t-equipe")).status_code == 403


def test_extrato_do_profissional_e_do_cliente(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    prof = amb.cliente.get("/v1/extrato", headers=cab("t-prof")).json()
    cli = amb.cliente.get("/v1/extrato", headers=cab("t-cliente")).json()
    outro = amb.cliente.get("/v1/extrato", headers=cab("t-outro-cliente")).json()

    assert [i["tipo"] for i in prof["itens"]] == ["retencao"]
    assert prof["itens"][0]["valor_centavos"] == 92_500
    assert {i["tipo"] for i in cli["itens"]} == {"cobranca", "retencao", "taxa"}
    assert outro["total"] == 0


def test_extrato_pagina(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO)
    amb.semear_dinheiro(100_000, taxa=7_500)

    r = amb.cliente.get("/v1/extrato?limite=1&deslocamento=1", headers=cab("t-cliente")).json()

    assert r["total"] == 3 and r["limite"] == 1 and len(r["itens"]) == 1
    assert amb.cliente.get("/v1/extrato?limite=0", headers=cab("t-cliente")).status_code == 422
    assert amb.cliente.get("/v1/extrato", headers=cab("t-equipe")).status_code == 403


def test_extrato_do_pedido(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    amb.semear_dinheiro(30_000)

    r = amb.cliente.get("/v1/pedidos/ped-1/extrato", headers=cab("t-prof")).json()

    assert r["total"] == 1
    assert r["itens"][0]["valor_centavos"] == 30_000
    assert isinstance(r["itens"][0]["valor_centavos"], int)
