"""B29 no Postgres: avaliação descartada ou em revisão some do perfil e de `etiquetas_top`."""

from __future__ import annotations

import pytest

from .test_fluxo_postgres import acao, foto
from .test_rotas_app_postgres import get, post
from .test_rotas_pedido_contrato_postgres import _em_andamento

pytestmark = pytest.mark.integracao


def _perfil(c) -> dict:
    return get(c, f"/v1/profissionais/{c.ids['profissional']}", "cliente").json()


def _total(perfil: dict, etiqueta: str) -> int:
    return next((x["total"] for x in perfil["etiquetas_top"] if x["etiqueta"] == etiqueta), 0)


def test_perfil_so_mostra_avaliacao_publicada(cenario):
    c = cenario
    pedido_id = _em_andamento(c)
    codigo = get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["codigo_conclusao"]
    out = acao(c, "profissional", pedido_id, "fazer_check_out",
               {"foto_final": foto("fim"), "codigo_conclusao": codigo})  # fmt: skip
    assert out.status_code == 200, out.text
    assert acao(c, "cliente", pedido_id, "confirmar_conclusao").status_code == 200

    antes = _perfil(c)
    base_limpo, base_n = _total(antes, "Limpo"), len(antes["avaliacoes"])
    r = post(
        c,
        f"/v1/pedidos/{pedido_id}/avaliacao",
        "cliente",
        {"nota_geral": 5, "etiquetas": ["Limpo"]},
    )
    assert r.status_code == 201, r.text
    avaliacao_id = r.json()["id"]

    publicada = _perfil(c)  # status padrão: publicada
    assert avaliacao_id in [a["id"] for a in publicada["avaliacoes"]]
    assert _total(publicada, "Limpo") == base_limpo + 1

    for status in ("em_revisao", "descartada"):
        with c.local.admin() as con:
            con.execute(
                "update public.avaliacoes set status = %s where id = %s", (status, avaliacao_id)
            )
        oculta = _perfil(c)
        assert avaliacao_id not in [a["id"] for a in oculta["avaliacoes"]], status
        assert len(oculta["avaliacoes"]) == base_n, status
        assert _total(oculta, "Limpo") == base_limpo, status

    with c.local.admin() as con:
        con.execute(
            "update public.avaliacoes set status = 'publicada' where id = %s", (avaliacao_id,)
        )
    assert avaliacao_id in [a["id"] for a in _perfil(c)["avaliacoes"]]
