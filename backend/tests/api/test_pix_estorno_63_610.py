"""BE-PIX-ESTORNO-6.3-6.10 (Termos 6.3 e 6.10): prazo do Pix e status/prazo estimado do estorno."""

# ruff: noqa: F811

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta

from conftest import AGORA, cab
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.pagamentos.modelos import EstadoCobranca, OrdemEstorno
from trato.pagamentos.prazos import PRAZO_ESTORNO_CARTAO, PRAZO_ESTORNO_PIX


def test_cobranca_pix_expoe_prazo_e_cartao_fica_nulo(fluxo):
    pid = fluxo.aceitar()
    # Pix em /v1/contratos/{id}/cobranca
    r_pix = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", json={"meio": "pix"})
    assert r_pix.status_code == 201, r_pix.text
    d = r_pix.json()
    assert d["pix_validade_minutos"] == 30
    assert datetime.fromisoformat(d["pix_expira_em"]) == datetime.fromisoformat(
        d["criada_em"]
    ) + timedelta(minutes=30)
    assert d["estorno_status"] is None and d["estorno_prazo_estimado"] is None

    # GET /v1/contratos/{id}/pagamento também expõe o prazo do Pix
    pgto = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert pgto["pix_validade_minutos"] == 30
    assert pgto["pix_expira_em"] == d["pix_expira_em"]

    # Cartão não traz prazo de Pix
    r_card = fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", json={"meio": "cartao"}
    )
    assert r_card.status_code == 201, r_card.text
    dc = r_card.json()
    assert dc["pix_expira_em"] is None and dc["pix_validade_minutos"] is None


def test_cobranca_em_rotas_pagamento_expoe_pix_e_estorno(fluxo):
    pid = fluxo.aceitar()
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", json={"meio": "pix"})
    assert r.status_code == 201, r.text
    c = r.json()
    assert c["pix_validade_minutos"] == 30
    assert c["pix_expira_em"] is not None
    assert c["estorno_status"] is None

    lista = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/cobrancas", headers=cab("t-cliente")).json()
    assert lista[-1]["pix_validade_minutos"] == 30


def test_estorno_status_e_prazo_estimado_pix_e_cartao(fluxo):
    # 1. Pix: solicitado -> em_processamento -> concluido
    pid = fluxo.aceitar()
    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", json={"meio": "pix"})
    cob_id = r.json()["cobranca_id"]
    fluxo.pagar(pid)

    ordem = OrdemEstorno("est-pix-1", pid, cob_id, 10_000, AGORA, estado="pendente")
    fluxo.servico.ordens.salvar(ordem)
    p1 = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert p1["estorno_status"] == "solicitado"
    assert p1["estorno_prazo_estimado"] == PRAZO_ESTORNO_PIX

    fluxo.servico.ordens.salvar(replace(ordem, estado="enviada", provedor_estorno_id="re_1"))
    p2 = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert p2["estorno_status"] == "em_processamento"
    assert p2["estorno_prazo_estimado"] == PRAZO_ESTORNO_PIX

    cob = fluxo.servico.cobrancas.obter(cob_id)
    fluxo.servico.cobrancas.salvar(replace(cob, estornado_centavos=10_000))
    p3 = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert p3["estorno_status"] == "concluido"
    assert p3["estorno_prazo_estimado"] == PRAZO_ESTORNO_PIX

    # 2. Cartão: devolvida / falhou
    fluxo.servico.cobrancas.salvar(
        replace(cob, meio=cob.meio.CARTAO, status=EstadoCobranca.DEVOLVIDA, estornado_centavos=0)
    )
    fluxo.servico.ordens.salvar(replace(ordem, estado="falhou"))
    p4 = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert p4["estorno_status"] == "falhou"
    assert p4["estorno_prazo_estimado"] == PRAZO_ESTORNO_CARTAO
