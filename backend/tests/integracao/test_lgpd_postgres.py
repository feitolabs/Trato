"""Testes de integração dos repositórios LGPD no Postgres local descartável (pgserver)."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from trato.lgpd.repositorios import Consentimento
from trato.persistencia.lgpd import criar_repositorios_lgpd_postgres

pytestmark = pytest.mark.integracao


def test_lgpd_repositorios_postgres(cenario):
    repos = criar_repositorios_lgpd_postgres(cenario.banco)
    user_id = cenario.ids["cliente"]

    # 1. Teste pendências
    pendencias = repos.fonte.pendencias(user_id)
    assert isinstance(pendencias, list)

    # 2. Teste exportar
    dados = repos.fonte.exportar(user_id)
    assert isinstance(dados, dict)
    assert "usuario" in dados

    # 3. Teste consentimento
    agora = datetime.now(UTC)
    c = Consentimento(
        usuario_id=user_id,
        finalidade="termos_uso",
        aceito=True,
        versao_texto="1.0",
        registrado_em=agora,
        ip="127.0.0.1",
    )
    repos.consentimentos.registrar(c)
    hist = repos.consentimentos.historico(user_id)
    assert any(h.finalidade == "termos_uso" for h in hist)
