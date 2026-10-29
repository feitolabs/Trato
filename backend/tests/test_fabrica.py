"""Fábrica do app: memória por padrão; Postgres só com a configuração completa."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from trato.api.fabrica import criar_app_da_config
from trato.config import Config


def config(**campos) -> Config:
    return Config(_env_file=None, **campos)


def test_padrao_e_memoria_e_nao_abre_conexao():
    assert config().trato_persistencia == "memoria"
    app = criar_app_da_config(config())
    # sem contexto ligado, as rotas respondem 503 (comportamento anterior preservado)
    assert TestClient(app).get("/v1/pedidos").status_code in (401, 503)


def test_modo_invalido_e_recusado():
    with pytest.raises(RuntimeError, match="TRATO_PERSISTENCIA"):
        criar_app_da_config(config(trato_persistencia="mongo"))


def test_postgres_sem_database_url_e_recusado():
    with pytest.raises(RuntimeError, match="DATABASE_URL"):
        criar_app_da_config(config(trato_persistencia="postgres"))


def test_postgres_sem_segredos_e_recusado():
    base = {"trato_persistencia": "postgres", "database_url": SecretStr("postgresql://x/y")}
    with pytest.raises(RuntimeError, match="TRATO_CODIGO_SEGREDO"):
        criar_app_da_config(config(**base))
    with pytest.raises(RuntimeError, match="SUPABASE_JWT_SECRET"):
        criar_app_da_config(config(**base, trato_codigo_segredo=SecretStr("a" * 16)))
