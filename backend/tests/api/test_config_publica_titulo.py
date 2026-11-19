"""Prazos e limites que o app mostra vêm da configuração; o pedido traz o título e, para o
profissional, o nome abreviado do cliente."""

from __future__ import annotations

from conftest import cab

from trato.api.servicos import nome_abreviado


def test_config_publica_devolve_os_prazos_da_configuracao(amb):
    r = amb.cliente.get("/v1/config/publica", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    j = r.json()
    cfg = amb.contexto.config.carregar()
    assert (
        j["validade_pedido_horas"] == cfg.prazos_pedido.receber_orcamentos.total_seconds() // 3600
    )
    assert j["prazo_confirmacao_cliente_horas"] == (
        cfg.prazos_pedido.confirmacao_cliente.total_seconds() // 3600
    )
    assert j["prazo_resposta_disputa_horas"] == cfg.disputas.prazo_resposta_horas
    assert j["prazo_retrabalho_atendimento_dias"] == cfg.garantias.prazo_atendimento_dias


def test_config_publica_nao_exige_login_e_nao_tem_dado_pessoal(amb):
    r = amb.cliente.get("/v1/config/publica")
    assert r.status_code == 200
    assert set(r.json()) == {
        "limite_orcamentos_por_pedido",
        "validade_pedido_horas",
        "prazo_confirmacao_cliente_horas",
        "prazo_retrabalho_atendimento_dias",
        "prazo_resposta_disputa_horas",
        "prazo_liberacao_dias",
        "suporte_email",
    }


def test_config_publica_traz_o_email_de_suporte_so_se_configurado(amb, monkeypatch):
    from trato.config import obter_config

    assert amb.cliente.get("/v1/config/publica").json()["suporte_email"] is None
    monkeypatch.setenv("TRATO_SUPORTE_EMAIL", "ajuda@exemplo.test")
    obter_config.cache_clear()
    try:
        assert amb.cliente.get("/v1/config/publica").json()["suporte_email"] == "ajuda@exemplo.test"
    finally:
        monkeypatch.delenv("TRATO_SUPORTE_EMAIL")
        obter_config.cache_clear()


def test_nome_abreviado():
    assert nome_abreviado("Gabriel Victor Lopes") == "Gabriel L."
    assert nome_abreviado("Ana") == "Ana"
    assert nome_abreviado("  ") is None
