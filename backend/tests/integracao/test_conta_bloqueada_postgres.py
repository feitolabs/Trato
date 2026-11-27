"""TERMOS-BE-ACESSO no Postgres local, com o login real (JWT): bloqueado recebe 403 com código;
atendimento e medidas continuam; o 401 não muda."""

from __future__ import annotations

from pathlib import Path

from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)


def _status(c, status: str) -> None:
    with c.local.admin() as con:
        con.execute(
            "update public.usuarios set status = %s where id = %s", (status, c.ids["cliente"])
        )


def test_bloqueado_recebe_403_e_so_o_atendimento_e_as_medidas_abrem(pg):  # noqa: F811
    http = pg.pagto[0]

    def get(url):
        return http.get(url, headers=pg.token("cliente"))

    assert get("/v1/me").status_code == 200
    _status(pg, "bloqueado")
    try:
        # A lista como cliente abre se houver pedido já contratado (20.6); como profissional, não.
        for url in ("/v1/me", "/v1/me/moedas", "/v1/pedidos?como=profissional"):
            r = get(url)
            assert r.status_code == 403, (url, r.text)
            assert r.json()["codigo"] == "conta_bloqueada", url
        for url in ("/v1/sac/chamados", "/v1/me/medidas"):
            assert get(url).status_code == 200, url
        assert http.get("/v1/me").status_code == 401
        falso = {"Authorization": "Bearer token-falso"}
        assert http.get("/v1/me", headers=falso).status_code == 401
    finally:
        _status(pg, "ativo")
    assert get("/v1/me").status_code == 200


def test_bloqueado_registra_e_remove_o_aparelho(pg):  # noqa: F811
    http = pg.pagto[0]
    # a tabela de aparelhos (já aplicada em produção) não está na lista do banco local
    migracoes = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
    with pg.local.admin() as con:
        if con.execute("select to_regclass('public.dispositivos_push')").fetchone()[0] is None:
            (arquivo,) = migracoes.glob("*_notificacoes_dispositivos_agendador.sql")
            con.execute(arquivo.read_text(encoding="utf-8"))
    token = {"token": "aparelho-de-teste-bloqueado-0123456789"}
    sql = "select count(*) from public.dispositivos_push where token = %s and ativo"

    def ativos() -> int:
        with pg.local.admin() as con:
            return con.execute(sql, (token["token"],)).fetchone()[0]

    _status(pg, "bloqueado")
    try:
        corpo = token | {"plataforma": "android"}
        r = http.post("/v1/dispositivos", json=corpo, headers=pg.token("cliente"))
        assert r.status_code == 204, r.text
        assert ativos() == 1
        r = http.request("DELETE", "/v1/dispositivos", json=token, headers=pg.token("cliente"))
        assert r.status_code == 204, r.text
        assert ativos() == 0
        r = http.get("/v1/notificacoes", headers=pg.token("cliente"))
        assert r.status_code == 403 and r.json()["codigo"] == "conta_bloqueada", r.text
    finally:
        _status(pg, "ativo")
