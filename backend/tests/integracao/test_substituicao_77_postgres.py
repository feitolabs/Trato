"""BE-SUBSTITUICAO-77 no Postgres local (migration 20261128014500_pedidos_substituicao_77.sql):
substituir pedido cancelado pelo profissional, imutabilidade de substitui_pedido_id no trigger e
consulta de faltas repetidas usando cancelamentos_pedido."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import psycopg
import pytest

from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401


def test_substituicao_e_faltas_repetidas_no_postgres(pg, equipe):
    http, contexto, _ = pg.pagto
    pid, _ = agendado(pg)

    # Profissional cancela
    r_can = http.post(
        f"/v1/pedidos/{pid}/acoes/cancelar",
        json={"prova": {"motivo": "Não poderei comparecer ao atendimento."}},
        headers=pg.token("profissional"),
    )
    assert r_can.status_code == 200, r_can.text

    # Outro usuário não pode substituir -> 403
    assert (
        http.post(
            f"/v1/pedidos/{pid}/substituir", headers=pg.token("profissional")
        ).status_code
        == 403
    )

    # Cliente cria pedido de substituição -> 201 com substitui_pedido_id gravado no banco
    r_sub = http.post(f"/v1/pedidos/{pid}/substituir", headers=pg.token("cliente"))
    assert r_sub.status_code == 201, r_sub.text
    novo = r_sub.json()
    assert novo["estado"] == "aberto" and novo["substitui_pedido_id"] == pid

    # Trigger protege substitui_pedido_id contra alteração
    with pytest.raises(psycopg.Error), pg.local.admin() as con:
        con.execute(
            "update public.pedidos set substitui_pedido_id = null where id = %s",
            (novo["id"],),
        )

    # Faltas repetidas no admin usando cancelamentos_pedido com tipo='cancelamento_profissional'
    pid2, _ = agendado(pg)
    with pg.local.admin() as con:
        con.execute("delete from public.cancelamentos_pedido")
        for p_ref in (pid, pid2):
            con.execute(
                "insert into public.cancelamentos_pedido "
                "(pedido_id, solicitado_por, papel_solicitante, tipo, status, motivo) "
                "values (%s, %s, 'profissional', 'cancelamento_profissional', "
                "'cancelado_sem_retencao', 'Falta registrada em teste')",
                (p_ref, pg.ids["profissional"]),
            )
    r_faltas = http.get(
        "/v1/admin/profissionais/faltas-repetidas?dias=90&minimo=2",
        headers=pg.token("med_a"),
    )
    assert r_faltas.status_code == 200, r_faltas.text
    itens = r_faltas.json()
    assert len(itens) == 1
    assert itens[0]["profissional_id"] == pg.ids["profissional"]
    assert itens[0]["total_cancelamentos"] == 2
