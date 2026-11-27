"""TERMOS-BE-REACEITE no Postgres local: histórico real, aceite idempotente e simultâneo."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import pytest

from trato.persistencia.lgpd import criar_repositorios_lgpd_postgres
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.instalacao import instalar_seguranca

from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def test_aceite_dos_termos_no_postgres(pg):  # noqa: F811
    http, contexto, _ = pg.pagto
    # Como em `trato.main`: a segurança é quem liga as rotas de LGPD.
    instalar_seguranca(http.app, ConfigSeguranca(_env_file=None))
    contexto.extras["banco"] = pg.banco
    contexto.extras["lgpd"] = criar_repositorios_lgpd_postgres(pg.banco)
    h = pg.token("cliente2")
    antes = http.get("/v1/me/termos", headers=h)
    assert antes.status_code == 200, antes.text
    assert antes.json()["aceite_pendente"] is True
    with ThreadPoolExecutor(max_workers=3) as pool:
        saidas = sorted(
            pool.map(
                lambda _: (
                    http.post("/v1/me/termos/aceite", json={"versao": "1.1"}, headers=h).status_code
                ),
                range(3),
            )
        )
    assert saidas == [200, 200, 201]
    assert http.get("/v1/me/termos", headers=h).json()["aceite_pendente"] is False
    assert linhas(
        pg,
        "select versao_texto from public.lgpd_consentimentos "
        "where usuario_id = %s and finalidade = 'termos_de_uso'",
        (pg.ids["cliente2"],),
    ) == [("1.1",)]
