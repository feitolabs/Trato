"""TERMOS-BE-86 sem as tabelas (memoria): painel responde 503 e o resto segue; permissoes."""

from __future__ import annotations

import pytest
from conftest import cab

URL = "/v1/admin/compensacoes"
CORPO = {"pedido_id": "ped-1", "valor_centavos": 100, "motivo": "Reembolso decidido depois."}


@pytest.mark.parametrize("quem", ["t-financeiro", "t-n1", "t-cliente", "t-prof"])
def test_sem_permissao_nao_registra_nem_cancela(amb, quem):
    assert amb.cliente.post(URL, json=CORPO, headers=cab(quem)).status_code == 403
    assert amb.cliente.get(URL, headers=cab(quem)).status_code == 403
    r = amb.cliente.post(f"{URL}/x/cancelar", json={"motivo": "m" * 12}, headers=cab(quem))
    assert r.status_code == 403


def test_sem_as_tabelas_503_com_codigo_e_lista_do_profissional_vazia(amb):
    for r in (
        amb.cliente.post(URL, json=CORPO, headers=cab("t-mediador")),
        amb.cliente.get(URL, headers=cab("t-mediador")),
    ):
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
    assert amb.cliente.get("/v1/me/compensacoes", headers=cab("t-prof")).json() == []
    assert amb.cliente.get("/v1/me/compensacoes", headers=cab("t-cliente")).status_code == 403


@pytest.mark.parametrize("ruim", [{"valor_centavos": 0}, {"valor_centavos": 1.5}, {"motivo": "x"}])
def test_valor_e_motivo_sao_conferidos(amb, ruim):
    r = amb.cliente.post(URL, json=CORPO | ruim, headers=cab("t-mediador"))
    assert r.status_code == 422
