"""BE-148-GUARDAS em memória: quem tem a permissão, e 503 sem o banco."""

# ruff: noqa: F811

from __future__ import annotations

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401

from trato.api.admin.papeis import PapelEquipe, Permissao, pode


def test_so_dpo_juridico_seguranca_e_administrador():
    com = {p for p in PapelEquipe if pode(p, Permissao.PEDIDO_GUARDAS_GERENCIAR)}
    assert com == {
        PapelEquipe.DPO,
        PapelEquipe.JURIDICO,
        PapelEquipe.SEGURANCA,
        PapelEquipe.ADMINISTRADOR,
    }


@pytest.mark.parametrize("resto", ["guardas", "retencao"])
def test_sem_o_banco_responde_503_e_cliente_nao_entra(adm, resto):
    url = f"/v1/admin/pedidos/ped-1/{resto}"
    assert adm.cliente.get(url, headers=cab("t-cliente")).status_code in (401, 403)
    r = adm.cliente.get(url, headers=cab(token_de("dpo")))
    assert r.status_code == 503, r.text
