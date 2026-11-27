"""BE-PAG-DEVOLVIDA: a consulta diz `devolvida` quando o valor voltou, e o pagamento do pedido
informa a validade do orçamento. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import datetime, timedelta

from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_orcamento_vencido import aceitar, aceito, orcamento, pagar_em

H = timedelta(hours=1)


def situacao(f, pid) -> dict:
    r = f.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente")
    assert r.status_code == 200, r.text
    return r.json()


def valores(f, pid) -> dict:
    r = f.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente")
    assert r.status_code == 200, r.text
    return r.json()


def test_cobranca_devolvida_aparece_como_devolvida(fluxo):
    pid = aceito(fluxo)
    assert situacao(fluxo, pid)["estado_pagamento"] == "sem_cobranca"
    cobranca = fluxo.cobrar(pid)
    assert situacao(fluxo, pid)["estado_pagamento"] == "aguardando_confirmacao"
    fluxo.amb.relogio.avancar(hours=2)
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200
    for _ in range(2):  # só leitura: repetir não muda nada
        dados = situacao(fluxo, pid)
        assert (dados["estado_pagamento"], dados["pago"]) == ("devolvida", False)
        assert dados["pago_centavos"] == 0 and dados["cobranca_id"] == cobranca["id"]
    assert valores(fluxo, pid)["cobranca_pendente_id"] is None
    (item,) = fluxo.chamar("GET", f"/v1/pedidos/{pid}/cobrancas", "t-cliente").json()
    assert item["status"] == "devolvida"


def test_pago_no_prazo_continua_pago(fluxo):
    pid = aceito(fluxo)
    cobranca = fluxo.cobrar(pid)
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200
    dados = situacao(fluxo, pid)
    assert (dados["estado_pagamento"], dados["pago"]) == ("pago", True)


def test_validade_do_orcamento_no_pagamento_do_pedido(fluxo):
    validade = fluxo.ctx.agora() + H
    pid, oid = orcamento(fluxo, validade)
    assert valores(fluxo, pid)["validade_ate"] is None  # ainda sem contrato
    assert aceitar(fluxo, pid, oid).status_code == 200
    assert datetime.fromisoformat(valores(fluxo, pid)["validade_ate"]) == validade


def test_sem_validade_vem_nulo(fluxo):
    pid, oid = orcamento(fluxo, None)
    assert aceitar(fluxo, pid, oid).status_code == 200
    dados = valores(fluxo, pid)
    assert "validade_ate" in dados and dados["validade_ate"] is None
