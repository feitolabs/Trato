"""B40: permissão exclusiva dos Tratinhos, CSV sem injeção de fórmula e download só do dono."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest
from admin_ambiente import adm, cab  # noqa: F401
from fastapi.testclient import TestClient

from trato.api.admin.papeis import MATRIZ, PapelEquipe, Permissao
from trato.api.admin.rotas_relatorios import _sanitizar_celula_csv, guardar_para_baixar

BASE = "/v1/admin"

_SCRIPT = Path(__file__).resolve().parents[3] / "harness" / "subir-backend-teste.py"
_spec = importlib.util.spec_from_file_location("subir_backend_teste_b40", _SCRIPT)
assert _spec and _spec.loader
amb = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = amb
_spec.loader.exec_module(amb)

CORPO = {"aviso_percentual": 75, "motivo": "Ajuste de segurança B40"}


@pytest.fixture
def painel():
    ambiente = amb.montar()
    http = TestClient(ambiente.app)

    def chamar(papel, metodo, caminho, **kw):
        cabecalho = {}
        if papel:
            r = http.post(
                "/auth/v1/token",
                params={"grant_type": "password"},
                json={"email": amb.email_de(papel), "password": amb.SENHA_TESTE},
                headers={"apikey": "anon-de-teste"},
            )
            assert r.status_code == 200, r.text
            cabecalho = {"Authorization": f"Bearer {r.json()['access_token']}"}
        return http.request(metodo, caminho, headers=cabecalho, **kw)

    return chamar


def test_matriz_moedas_configurar_so_admin_e_financeiro():
    com = {p for p, perms in MATRIZ.items() if Permissao.MOEDAS_CONFIGURAR in perms}
    assert com == {PapelEquipe.ADMINISTRADOR, PapelEquipe.FINANCEIRO}


@pytest.mark.parametrize(
    ("papel", "esperado"), [("moderador", 403), ("financeiro", 200), ("administrador", 200)]
)
def test_put_config_moedas_por_papel(painel, papel, esperado):
    atual = painel("administrador", "GET", f"{BASE}/moedas/config").json()
    r = painel(papel, "PUT", f"{BASE}/moedas/config", json={**atual, **CORPO})
    assert r.status_code == esperado, r.text


@pytest.mark.parametrize(
    "texto", ["=cmd|' /C calc'!A0", "+1+1", "@SUM(A1:A2)", "-2+3", "\tx", "\rx"]
)
def test_celula_perigosa_ganha_apostrofo(texto):
    assert _sanitizar_celula_csv(texto) == "'" + texto


@pytest.mark.parametrize("valor", ["Maria", "", "-12,50", "1.234,56", 10, -5, None, "João =x"])
def test_celula_segura_nao_muda(valor):
    assert _sanitizar_celula_csv(valor) == valor


def test_baixar_sem_token_401_outro_operador_403_dono_200(adm):  # noqa: F811
    codigo = guardar_para_baixar(b"a;b\n", "x.csv", "eq-financeiro", "text/csv")
    url = f"{BASE}/relatorios/baixar/{codigo}"

    assert adm.cliente.get(url).status_code == 401
    assert adm.cliente.get(url, headers=cab("t-administrador")).status_code == 403
    # o 403 não gasta o código: o dono ainda baixa, uma vez só
    ok = adm.cliente.get(url, headers=cab("t-financeiro"))
    assert ok.status_code == 200 and ok.content == b"a;b\n"
    assert adm.cliente.get(url, headers=cab("t-financeiro")).status_code == 404
