"""Backend de teste (o mesmo de `harness/subir-backend-teste.py`) + cliente HTTP que imita o painel."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

_SCRIPT = Path(__file__).resolve().parents[3] / "harness" / "subir-backend-teste.py"
_spec = importlib.util.spec_from_file_location("subir_backend_teste", _SCRIPT)
assert _spec and _spec.loader
amb = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = amb
_spec.loader.exec_module(amb)


class Painel:
    """Faz o que o `ApiAdminHttp` do painel faz: login em /auth/v1/token e Bearer em tudo."""

    def __init__(self, ambiente) -> None:
        self.ambiente = ambiente
        self.http = TestClient(ambiente.app)

    def entrar(self, papel: str) -> str:
        r = self.http.post(
            "/auth/v1/token", params={"grant_type": "password"},
            json={"email": amb.email_de(papel), "password": amb.SENHA_TESTE}, headers={"apikey": "anon-de-teste"},
        )  # fmt: skip
        assert r.status_code == 200, r.text
        return r.json()["access_token"]

    def chamar(self, papel: str | None, metodo: str, caminho: str, **kw):
        cab = {"Authorization": f"Bearer {self.entrar(papel)}"} if papel else {}
        return self.http.request(metodo, caminho, headers=cab, **kw)


@pytest.fixture
def ambiente():
    return amb.montar()


@pytest.fixture
def painel(ambiente) -> Painel:
    return Painel(ambiente)
