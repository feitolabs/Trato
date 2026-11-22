"""B32 no Postgres: grava nota_decimal, rejeita incoerente (422) e recalcula nota_publica."""

from __future__ import annotations

from decimal import Decimal

import pytest

from .test_fluxo_postgres import acao, foto
from .test_rotas_app_postgres import get, post
from .test_rotas_pedido_contrato_postgres import _em_andamento

pytestmark = pytest.mark.integracao


def _concluir(c) -> str:
    pedido_id = _em_andamento(c)
    codigo = get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["codigo_conclusao"]
    out = acao(
        c,
        "profissional",
        pedido_id,
        "fazer_check_out",
        {"foto_final": foto("fim"), "codigo_conclusao": codigo},
    )
    assert out.status_code == 200, out.text
    assert acao(c, "cliente", pedido_id, "confirmar_conclusao").status_code == 200
    return pedido_id


def test_nota_decimal_grava_recalcula_media_e_aceita_ausente_no_postgres(cenario):
    c = cenario
    # Limpa avaliações anteriores do profissional no banco compartilhado para média exata.
    with c.local.admin() as con:
        con.execute(
            "delete from public.avaliacoes where avaliado_id = %s", (c.ids["profissional"],)
        )

    pedido_1 = _concluir(c)
    # 4.2 com nota_geral 5 -> 422
    invalida = post(
        c,
        f"/v1/pedidos/{pedido_1}/avaliacao",
        "cliente",
        {"nota_geral": 5, "nota_decimal": 4.2},
    )
    assert invalida.status_code == 422, invalida.text

    # 4.8 com nota_geral 5 -> 201, grava 4.80 e nota_publica vira 4.8
    ok = post(
        c,
        f"/v1/pedidos/{pedido_1}/avaliacao",
        "cliente",
        {"nota_geral": 5, "nota_decimal": 4.8},
    )
    assert ok.status_code == 201, ok.text
    assert ok.json()["nota_decimal"] == 4.8

    with c.local.admin() as con:
        linha = con.execute(
            "select nota_geral, nota_decimal from public.avaliacoes where id = %s",
            (ok.json()["id"],),
        ).fetchone()
    assert linha == (5, Decimal("4.80"))

    perfil_1 = get(c, f"/v1/profissionais/{c.ids['profissional']}", "cliente").json()
    assert perfil_1["nota_publica"] == 4.8

    # Segundo pedido sem nota_decimal -> grava NULL e média combina 4.80 + 4 = 4.40
    pedido_2 = _concluir(c)
    sem_dec = post(c, f"/v1/pedidos/{pedido_2}/avaliacao", "cliente", {"nota_geral": 4})
    assert sem_dec.status_code == 201, sem_dec.text
    assert sem_dec.json()["nota_decimal"] is None

    with c.local.admin() as con:
        linha2 = con.execute(
            "select nota_geral, nota_decimal from public.avaliacoes where id = %s",
            (sem_dec.json()["id"],),
        ).fetchone()
    assert linha2 == (4, None)

    perfil_2 = get(c, f"/v1/profissionais/{c.ids['profissional']}", "cliente").json()
    assert perfil_2["nota_publica"] == 4.4
