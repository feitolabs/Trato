"""BE-FORCA-MAIOR-78 no Postgres local (migration 20261128020000_eventos_forca_maior.sql):
solicitar, listar, aprovar cancelar com estorno integral, recusar, idempotência, imutabilidade
no trigger e 503 sem tabela."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid

import psycopg
import pytest

from trato.pedidos.estados import Estado as E
from trato.persistencia.forca_maior import ForcaMaiorPostgres

from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

DESC = "Queda de energia generalizada no bairro impediu a execução do serviço."
JUST = "Evento externo confirmado pela equipe com base nos comprovantes."


def _limpar(pg):
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.eventos_forca_maior")


@pytest.fixture
def ambiente_fm(pg, equipe):
    _limpar(pg)
    yield pg
    _limpar(pg)


def test_forca_maior_fluxo_completo_no_postgres(ambiente_fm, monkeypatch):
    c = ambiente_fm
    http, contexto, _ = c.pagto
    pid, _ = agendado(c)

    r_sol = http.post(
        f"/v1/pedidos/{pid}/forca-maior",
        json={"acao_solicitada": "cancelar", "descricao": DESC, "comprovantes": ["arq-1"]},
        headers=c.token("cliente"),
    )
    assert r_sol.status_code == 201, r_sol.text
    ev = r_sol.json()

    assert (
        http.post(
            f"/v1/admin/forca-maior/{ev['id']}/decisao",
            json={
                "decisao": "aprovado",
                "justificativa": JUST,
                "chave_idempotencia": f"ch-pg-fm-{uuid.uuid4().hex}",
            },
            headers=c.token("cliente"),
        ).status_code
        == 403
    )

    chave = f"ch-pg-fm-{uuid.uuid4().hex}"
    r_dec = http.post(
        f"/v1/admin/forca-maior/{ev['id']}/decisao",
        json={"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": chave},
        headers=c.token("adm_a"),
    )
    assert r_dec.status_code == 200, r_dec.text
    assert r_dec.json()["status"] == "aprovado" and r_dec.json()["idempotente"] is False
    assert contexto.pedidos.obter(pid).estado is E.CANCELADO
    saldos = contexto.ledger.saldos_pedido(pid, c.ids["profissional"])
    assert saldos.retido == 0 and saldos.a_liberar == 0

    r_idem = http.post(
        f"/v1/admin/forca-maior/{ev['id']}/decisao",
        json={"decisao": "aprovado", "justificativa": JUST, "chave_idempotencia": chave},
        headers=c.token("adm_a"),
    )
    assert r_idem.status_code == 200 and r_idem.json()["idempotente"] is True

    with pytest.raises(psycopg.Error), c.local.admin() as con:
        con.execute(
            "update public.eventos_forca_maior set status = 'recusado' where id = %s",
            (ev["id"],),
        )

    pid2, _ = agendado(c)
    ev2 = http.post(
        f"/v1/pedidos/{pid2}/forca-maior",
        json={"acao_solicitada": "reagendar", "descricao": DESC, "comprovantes": []},
        headers=c.token("profissional"),
    ).json()
    r_rec = http.post(
        f"/v1/admin/forca-maior/{ev2['id']}/decisao",
        json={
            "decisao": "recusado",
            "justificativa": JUST,
            "chave_idempotencia": f"ch-pg-rec-{uuid.uuid4().hex}",
        },
        headers=c.token("adm_a"),
    )
    assert r_rec.status_code == 200 and r_rec.json()["status"] == "recusado"

    monkeypatch.setattr(ForcaMaiorPostgres, "_existe", staticmethod(lambda _con: False))
    assert http.get("/v1/admin/forca-maior", headers=c.token("med_a")).status_code == 503
    assert http.get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).status_code == 200
