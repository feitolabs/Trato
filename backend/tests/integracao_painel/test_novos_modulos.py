"""Testes de integração para os novos módulos administrativos (1 a 7)."""

from __future__ import annotations


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

    r_ser = painel.chamar(
        "administrador", "GET", "/v1/admin/dashboard/series", params={"dias": "7"}
    )
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
    corpo = {"formato": "excel_br", "motivo": "Fechamento contábil do mês"}
    assert (
        painel.chamar(None, "POST", "/v1/admin/relatorios/financeiro", json=corpo).status_code
        == 401
    )
    r = painel.chamar("administrador", "POST", "/v1/admin/relatorios/financeiro", json=corpo)
    assert r.status_code in (201, 503)
    if r.status_code == 201:
        pronto = r.json()
        baixado = painel.http.get(f"/v1/admin/relatorios/baixar/{pronto['codigo']}")
        assert baixado.status_code == 200
        assert baixado.text.startswith("﻿ID_Pagamento;Data;")
        assert "attachment; filename=" in baixado.headers.get("Content-Disposition", "")
        # o código vale uma vez só
        assert painel.http.get(f"/v1/admin/relatorios/baixar/{pronto['codigo']}").status_code == 404


def test_token_na_url_nao_autentica(painel):
    token = painel.entrar("administrador")
    corpo = {"motivo": "Fechamento contábil do mês"}
    r = painel.http.post(f"/v1/admin/relatorios/financeiro?token={token}", json=corpo)
    assert r.status_code == 401


def test_moedas_config_ver_e_alterar(painel):
    assert painel.chamar(None, "GET", "/v1/admin/moedas/config").status_code == 401
    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/config")
    assert r.status_code == 200 and r.json()["ativo"] is False
    corpo = {
        "ativo": True,
        "bonus_avaliacao_moedas": 30,
        "valor_moeda_centavos": 1,
        "teto_mensal_moedas": 300,
        "min_servico_centavos": 8000,
        "max_bonus_por_profissional_mes": 1,
        "max_desconto_percentual": 20,
        "validade_dias": None,
        "motivo": "Teste de ligar as moedas",
    }
    assert painel.chamar("administrador", "PUT", "/v1/admin/moedas/config", json=corpo).status_code == 200
    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/config")
    assert r.json()["bonus_avaliacao_moedas"] == 30 and r.json()["ativo"] is True
    sem_motivo = {**corpo, "motivo": "curto"}
    assert painel.chamar("administrador", "PUT", "/v1/admin/moedas/config", json=sem_motivo).status_code == 422


def test_painel_le_e_altera_os_pesos_com_motivo(painel):
    url = "/v1/admin/ranking/config"
    assert painel.chamar(None, "GET", url).status_code == 401
    r = painel.chamar("administrador", "GET", url)
    assert r.status_code == 200 and r.json()["peso_nota"] == 60
    corpo = {
        "nota_prior": 4.2,
        "prior_avaliacoes": 8,
        "volume_referencia": 30,
        "peso_nota": 50,
        "peso_volume": 30,
        "peso_verificacao": 10,
        "peso_disponivel": 10,
        "motivo": "Dar mais peso ao volume de serviços",
    }
    assert painel.chamar("administrador", "PUT", url, json=corpo).status_code == 200
    assert painel.chamar("administrador", "GET", url).json()["peso_volume"] == 30
    curto = {**corpo, "motivo": "curto"}
    assert painel.chamar("administrador", "PUT", url, json=curto).status_code == 422
    zerado = {**corpo, "peso_nota": 0, "peso_volume": 0, "peso_verificacao": 0, "peso_disponivel": 0}
    assert painel.chamar("administrador", "PUT", url, json=zerado).status_code == 422
    fora = {**corpo, "nota_prior": 7}
    assert painel.chamar("administrador", "PUT", url, json=fora).status_code == 422
