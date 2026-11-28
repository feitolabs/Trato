"""BE-MARKETING-154 no Postgres local: estimativa e disparo pela mesma regra de consentimento."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from trato.lgpd.repositorios import Consentimento

from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

BASE = "/v1/admin/notificacoes"
CAMPANHAS = "select count(*) from public.campanhas_notificacao"


@pytest.fixture
def limpo(pg, equipe):
    """Apaga o que o teste criou (só no banco descartável)."""

    def apagar():
        with pg.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute("delete from public.lgpd_consentimentos where versao_texto = 'mkt-154'")
            con.execute("delete from public.notificacoes where tipo = 'aviso_campanha'")
            con.execute("delete from public.campanhas_notificacao")

    apagar()
    yield pg
    apagar()


def consentir(c, aceito: bool, quando: datetime) -> None:
    c.pagto[1].extras["lgpd"].consentimentos.registrar(
        Consentimento(c.ids["cliente"], "comunicacoes_marketing", aceito, "mkt-154", quando)
    )


def estimar(c, tipo="marketing"):
    url = f"{BASE}/estimativa?segmento=todos&tipo={tipo}"
    return c.pagto[0].get(url, headers=c.token("adm_a"))


def disparar(c, tipo="marketing"):
    corpo = {
        "titulo": "Novidade",
        "mensagem": "Uma novidade do Trato.",
        "segmento": "todos",
        "tipo": tipo,
        "motivo": "Campanha de teste do consentimento.",
    }
    return c.pagto[0].post(f"{BASE}/disparar", json=corpo, headers=c.token("adm_a"))


def recebeu(c, campanha: str) -> list:
    return linhas(
        c,
        "select dados from public.notificacoes where usuario_id = %s "
        "and dados->>'campanha_id' = %s",
        (c.ids["cliente"], campanha),
    )


def test_so_recebe_com_o_ultimo_registro_aceito(limpo):
    c = limpo
    agora = datetime.now(UTC)
    total = estimar(c, "operacional").json()["destinatarios"]
    vazio = estimar(c).json()
    assert vazio == {"destinatarios": 0, "desativaram": total}
    assert disparar(c).status_code == 422  # ninguém consentiu
    for aceito in (True, False, True):  # aceitou, revogou, reaceitou (mesmo instante: id)
        consentir(c, aceito, agora)
        previsto = estimar(c).json()
        assert previsto == {"destinatarios": int(aceito), "desativaram": total - int(aceito)}
        r = disparar(c)
        if not aceito:
            assert r.status_code == 422, r.text
            continue
        assert r.status_code == 201 and r.json()["total_destinatarios"] == 1, r.text
        ((dados,),) = recebeu(c, r.json()["id"])
        assert dados["tela"] == "privacidade" and dados["link"].endswith("privacidade")
    operacional = disparar(c, "operacional")
    assert operacional.json()["total_destinatarios"] == total
    ((dados,),) = recebeu(c, operacional.json()["id"])
    assert "tela" not in dados


def test_push_desligado_fica_de_fora_e_erro_de_leitura_nao_envia(limpo, monkeypatch):
    c = limpo
    consentir(c, True, datetime.now(UTC))
    with c.local.admin() as con:
        antes = con.execute(
            "select preferencias from public.notificacao_preferencias where usuario_id = %s",
            (c.ids["cliente"],),
        ).fetchone()
        con.execute(
            "insert into public.notificacao_preferencias (usuario_id, preferencias) values "
            '(%s, \'{"marketing": {"push": false}}\') on conflict (usuario_id) do update '
            "set preferencias = excluded.preferencias",
            (c.ids["cliente"],),
        )
    try:
        assert estimar(c).json()["destinatarios"] == 0 and disparar(c).status_code == 422
    finally:
        with c.local.admin() as con:
            con.execute(
                "delete from public.notificacao_preferencias where usuario_id = %s and %s",
                (c.ids["cliente"], antes is None),
            )

    def quebrar(*_):
        raise RuntimeError("sem leitura")

    monkeypatch.setattr(c.pagto[1].extras["lgpd"].consentimentos, "ultimos", quebrar)
    for r in (estimar(c), disparar(c)):
        assert r.status_code == 503, r.text
    assert linhas(c, CAMPANHAS) == [(0,)]
    assert estimar(c, "operacional").status_code == 200  # operacional não lê consentimento
