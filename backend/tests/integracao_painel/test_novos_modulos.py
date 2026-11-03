"""Testes de integração para os novos módulos administrativos (1 a 7)."""

from __future__ import annotations

import pytest


def test_dashboard_metricas_e_series(painel):
    # Sem auth -> 401
    assert painel.chamar(None, "GET", "/v1/admin/dashboard/metricas").status_code == 401

    r_met = painel.chamar("administrador", "GET", "/v1/admin/dashboard/metricas")
    assert r_met.status_code in (200, 503)
    if r_met.status_code == 200:
        dados_met = r_met.json()
        assert "gmv_centavos" in dados_met
        assert "receita_taxa_centavos" in dados_met
        assert "pedidos_total" in dados_met

    r_ser = painel.chamar("administrador", "GET", "/v1/admin/dashboard/series", params={"dias": "7"})
    assert r_ser.status_code in (200, 503)
    if r_ser.status_code == 200:
        dados_ser = r_ser.json()
        assert "historico_dias" in dados_ser
        assert len(dados_ser["historico_dias"]) == 7


def test_risco_alertas(painel):
    assert painel.chamar(None, "GET", "/v1/admin/risco/alertas").status_code == 401
    r = painel.chamar("administrador", "GET", "/v1/admin/risco/alertas")
    assert r.status_code in (200, 503)
    if r.status_code == 200:
        assert isinstance(r.json(), list)


def test_cupons_listar(painel):
    assert painel.chamar(None, "GET", "/v1/admin/cupons").status_code == 401
    r = painel.chamar("administrador", "GET", "/v1/admin/cupons")
    assert r.status_code in (200, 503)
    if r.status_code == 200:
        assert isinstance(r.json(), list)


def test_equipe_listar(painel):
    assert painel.chamar(None, "GET", "/v1/admin/equipe").status_code == 401
    r = painel.chamar("administrador", "GET", "/v1/admin/equipe")
    assert r.status_code in (200, 503)
    if r.status_code == 200:
        assert isinstance(r.json(), list)


def test_notificacoes_campanhas(painel):
    assert painel.chamar(None, "GET", "/v1/admin/notificacoes/campanhas").status_code == 401
    r = painel.chamar("administrador", "GET", "/v1/admin/notificacoes/campanhas")
    assert r.status_code in (200, 503)
    if r.status_code == 200:
        assert isinstance(r.json(), list)


def test_relatorios_csv(painel):
    assert painel.chamar(None, "GET", "/v1/admin/relatorios/financeiro").status_code == 401
    r_fin = painel.chamar("administrador", "GET", "/v1/admin/relatorios/financeiro")
    assert r_fin.status_code in (200, 503)
    if r_fin.status_code == 200:
        assert "ID_Pagamento;Data_Criacao;" in r_fin.text


def test_relatorios_download_via_query_token(painel):
    token = painel.entrar("administrador")
    # Autenticação via query param ?token=... (como o navegador faz ao clicar no botão de download)
    r_fin = painel.http.get(f"/v1/admin/relatorios/financeiro?token={token}")
    assert r_fin.status_code in (200, 503)
    assert r_fin.status_code != 401
    if r_fin.status_code == 200:
        assert "ID_Pagamento;Data_Criacao;" in r_fin.text
        assert "attachment; filename=" in r_fin.headers.get("Content-Disposition", "")
