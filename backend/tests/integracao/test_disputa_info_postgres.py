"""BE-DISPUTA-INFO-84 no Postgres local (migration 20261128013000_disputa_pedidos_informacao.sql):
solicitar com prazo >= 10 dias úteis, responder pelo destinatário certo, bloquear outro papel,
encerrar sem resposta só após vencimento, imutabilidade no trigger e 503 sem tabela."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import psycopg
import pytest

from trato.persistencia.disputa_pedidos_info import DisputaPedidosInfoPostgres

from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

MSG = "Envie comprovantes adicionais para análise da disputa."


def _limpar(pg):
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.disputa_pedidos_informacao")


@pytest.fixture
def ambiente_info(pg, equipe):
    _limpar(pg)
    yield pg
    _limpar(pg)


def test_pedido_info_fluxo_completo_imutabilidade_e_sem_tabela_no_postgres(
    ambiente_info, monkeypatch
):
    c = ambiente_info
    http, contexto, _ = c.pagto
    pid, _ = agendado(c)
    check_in(c, pid)
    r_disp = http.post(
        f"/v1/pedidos/{pid}/disputa",
        json={"motivo": "mal_feito", "descricao": "A pintura ficou manchada."},
        headers=c.token("cliente"),
    )
    assert r_disp.status_code == 201, r_disp.text

    with c.local.admin() as con:
        disputa_id = str(
            con.execute("select id from public.disputas where pedido_id = %s", (pid,)).fetchone()[0]
        )

    # 1. Solicitar informação ao cliente usando disputa_id real
    r_sol = http.post(
        f"/v1/admin/disputas/{disputa_id}/pedidos-informacao",
        json={"destinatario_papel": "cliente", "mensagem": MSG},
        headers=c.token("med_a"),
    )
    assert r_sol.status_code == 201, r_sol.text
    info1 = r_sol.json()
    assert info1["disputa_id"] == disputa_id and info1["status"] == "aguardando_resposta"

    # Profissional (outro papel) tentando responder -> 403
    assert (
        http.post(
            f"/v1/disputas/{disputa_id}/pedidos-informacao/{info1['id']}/responder",
            json={"resposta_texto": "Não sou o destinatário"},
            headers=c.token("profissional"),
        ).status_code
        == 403
    )

    # Cliente responde -> 200
    r_resp = http.post(
        f"/v1/disputas/{disputa_id}/pedidos-informacao/{info1['id']}/responder",
        json={"resposta_texto": "Comprovantes anexados e descritos."},
        headers=c.token("cliente"),
    )
    assert r_resp.status_code == 200, r_resp.text
    assert r_resp.json()["status"] == "respondido"

    # Trigger de imutabilidade no banco bloqueia alterar resposta já gravada
    with pytest.raises(psycopg.Error), c.local.admin() as con:
        con.execute(
            "update public.disputa_pedidos_informacao set resposta_texto = 'alterado' where id = %s",
            (info1["id"],),
        )

    # 2. Segundo pedido (ao profissional): encerrar antes do prazo falha (409), depois passa (200)
    r_sol2 = http.post(
        f"/v1/admin/disputas/{disputa_id}/pedidos-informacao",
        json={"destinatario_papel": "profissional", "mensagem": MSG},
        headers=c.token("med_a"),
    )
    assert r_sol2.status_code == 201, r_sol2.text
    info2 = r_sol2.json()
    url_enc2 = (
        f"/v1/admin/disputas/{disputa_id}/pedidos-informacao/{info2['id']}/encerrar-sem-resposta"
    )
    assert (
        http.post(
            url_enc2,
            json={"motivo": "Tentativa antes de vencer o prazo."},
            headers=c.token("med_a"),
        ).status_code
        == 409
    )

    # Avança o relógio do contexto para após responder_ate e encerra sem resposta
    agora_original = contexto.agora
    futuro = agora_original() + timedelta(days=25)
    contexto.agora = lambda: futuro
    try:
        r_enc2 = http.post(
            url_enc2,
            json={"motivo": "Prazo de 10 dias úteis vencido sem retorno."},
            headers=c.token("med_a"),
        )
        assert r_enc2.status_code == 200, r_enc2.text
        assert r_enc2.json()["status"] == "encerrado_sem_resposta"
    finally:
        contexto.agora = agora_original

    # Responder após encerrado -> 409
    assert (
        http.post(
            f"/v1/disputas/{disputa_id}/pedidos-informacao/{info2['id']}/responder",
            json={"resposta_texto": "Tarde demais"},
            headers=c.token("profissional"),
        ).status_code
        == 409
    )

    # 3. Sem a tabela -> 503 sem quebrar o detalhe da disputa
    monkeypatch.setattr(DisputaPedidosInfoPostgres, "_existe", staticmethod(lambda _con: False))
    assert (
        http.get(
            f"/v1/admin/disputas/{disputa_id}/pedidos-informacao", headers=c.token("med_a")
        ).status_code
        == 503
    )
    assert http.get(f"/v1/pedidos/{pid}/disputa", headers=c.token("cliente")).status_code == 200
