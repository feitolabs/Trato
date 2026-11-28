"""BE-SELO-103-RELATO-84 no Postgres local (20261127223000 e 20261127223100): funções do selo,
aprovação recusada com retirada aberta e o resultado esperado imutável."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid

import psycopg
import pytest

from trato.api.admin.postgres import criar_admin_postgres
from trato.persistencia.erros import SeloRetirado

from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

NIVEL = "select nivel_verificacao from public.perfis_profissional where usuario_id = %s"


@pytest.fixture
def selo(pg, equipe):
    """Profissional com selo; no fim, apaga o histórico (só no banco descartável)."""
    pro = pg.ids["profissional"]
    with pg.local.admin() as con:
        antes = con.execute(NIVEL, (pro,)).fetchone()[0]
        con.execute(
            "update public.perfis_profissional set nivel_verificacao = 'verificado' "
            "where usuario_id = %s",
            (pro,),
        )
    yield pg
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.selo_eventos")
        con.execute(
            "update public.perfis_profissional set nivel_verificacao = %s where usuario_id = %s",
            (antes, pro),
        )


def nivel(c) -> str:
    with c.local.admin() as con:
        return con.execute(NIVEL, (c.ids["profissional"],)).fetchone()[0]


def acao(c, nome, chave, quem="adm_a"):
    url = f"/v1/admin/profissionais/{c.ids['profissional']}/selo/{nome}"
    corpo = {"motivo": "A conferência de identidade falhou.", "chave_idempotencia": chave}
    return c.pagto[0].post(url, json=corpo, headers=c.token(quem))


def test_retirada_trava_a_aprovacao_ate_regularizar(selo):
    c = selo
    chave = f"chave-{uuid.uuid4().hex}"
    assert acao(c, "retirar", chave, "med_a").status_code == 403
    r = acao(c, "retirar", chave)
    assert r.status_code == 200 and r.json()["resultado"] == "ok", r.text
    assert acao(c, "retirar", chave).json()["resultado"] == "ja_existe"
    assert nivel(c) == "basico" and c.pagto[1].selos.retirada_aberta(c.ids["profissional"])
    with c.local.admin() as con:
        vid = str(
            con.execute(
                "insert into public.verificacoes (profissional_id, nivel_solicitado, "
                "consentimento_lgpd_em) values (%s, 'verificado', now()) returning id",
                (c.ids["profissional"],),
            ).fetchone()[0]
        )
    url = f"/v1/admin/verificacoes/{vid}/decisao"
    corpo = {"aprovar": True, "motivo": "Documentos conferidos."}
    r = c.pagto[0].post(url, json=corpo, headers=c.token("adm_a"))
    assert r.status_code == 409 and r.json()["codigo"] == "selo_retirado", r.text
    # Mesmo sem a conferência da rota (corrida), o banco recusa e desfaz a decisão inteira.
    with pytest.raises(SeloRetirado):
        criar_admin_postgres(c.banco).verificacoes.decidir(
            vid, c.ids["adm_a"], True, "Documentos conferidos."
        )
    with c.local.admin() as con:
        status = con.execute(
            "select status from public.verificacoes where id = %s", (vid,)
        ).fetchone()[0]
    assert status == "enviada" and nivel(c) == "basico"
    r = acao(c, "reconferencia", f"chave-{uuid.uuid4().hex}")
    assert r.status_code == 200, r.text
    r = acao(c, "regularizar", f"chave-{uuid.uuid4().hex}")
    assert r.status_code == 200 and r.json()["nivel_verificacao"] == "verificado", r.text
    assert nivel(c) == "verificado" and r.json()["retirada_aberta"] is False
    assert acao(c, "regularizar", f"chave-{uuid.uuid4().hex}").status_code == 409
    assert acao(c, "retirar", chave).json()["resultado"] == "ja_existe"
    assert nivel(c) == "verificado"  # repetir a chave antiga não retira de novo


def test_resultado_esperado_gravado_na_abertura_e_imutavel(pg, equipe):
    pid, _ = agendado(pg)
    check_in(pg, pid)
    http, contexto, _ = pg.pagto
    corpo = {
        "motivo": "mal_feito",
        "descricao": "A pintura ficou manchada.",
        "resultado_esperado": "retrabalho",
    }
    r = http.post(f"/v1/pedidos/{pid}/disputa", json=corpo, headers=pg.token("cliente"))
    assert r.status_code < 300, r.text
    assert contexto.disputas.obter(pid).resultado_esperado == "retrabalho"
    assert (
        dict(contexto.disputas.listar())[
            next(
                k
                for k, _ in contexto.disputas.listar()
                if k.replace("-", "") == pid.replace("-", "")
            )
        ].resultado_esperado
        == "retrabalho"
    )
    visto = http.get(f"/v1/pedidos/{pid}/disputa", headers=pg.token("cliente")).json()
    assert visto["resultado_esperado"] == "retrabalho"
    with pytest.raises(psycopg.Error), pg.local.admin() as con:
        con.execute(
            "update public.disputas set resultado_esperado = 'reembolso_total' "
            "where pedido_id = %s",
            (pid,),
        )
