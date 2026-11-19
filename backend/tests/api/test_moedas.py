"""Moedas do Trato (fase 1): bônus por avaliar, teto mensal, idempotência e saldo."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, cab

from trato.api.moedas import ConfigMoedas, MoedasEmMemoria, conceder_bonus_avaliacao
from trato.pedidos.estados import Estado


def post(amb, url, token, corpo=None):
    return amb.cliente.post(url, json=corpo, headers=cab(token))


def ligar(amb, **cfg):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))


def test_desligado_por_padrao_nao_da_moedas(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = post(amb, "/v1/pedidos/ped-1/avaliacao", "t-cliente", {"nota_geral": 5})
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 0


def test_cliente_ganha_bonus_ao_avaliar_e_ve_saldo(amb):
    ligar(amb, bonus_avaliacao_moedas=50, valor_moeda_centavos=2)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = post(amb, "/v1/pedidos/ped-1/avaliacao", "t-cliente", {"nota_geral": 5})
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 50
    m = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()
    assert m["saldo"] == 50 and m["valor_moeda_centavos"] == 2
    assert m["extrato"][0]["tipo"] == "bonus_avaliacao"


def test_profissional_avaliando_nao_ganha(amb):
    ligar(amb)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    r = post(amb, "/v1/pedidos/ped-1/avaliacao", "t-prof", {"nota_geral": 4})
    assert r.status_code == 201 and r.json()["moedas_ganhas"] == 0


def test_bonus_e_idempotente_por_pedido():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True))
    a = conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p", agora=AGORA)
    b = conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p", agora=AGORA)
    assert a == 50 and b == 0 and repo.saldo("c", AGORA) == 50


def test_teto_mensal_corta_o_bonus():
    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, bonus_avaliacao_moedas=50, teto_mensal_moedas=80)
    )
    assert conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p1", agora=AGORA) == 50
    assert conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p2", agora=AGORA) == 30
    assert conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p3", agora=AGORA) == 0


def test_validade_expira_o_saldo():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, validade_dias=10))
    conceder_bonus_avaliacao(repo, cliente_id="c", valor_servico_centavos=10_000, pedido_id="p", agora=AGORA)
    assert repo.saldo("c", AGORA + timedelta(days=9)) == 50
    assert repo.saldo("c", AGORA + timedelta(days=11)) == 0


def test_servico_abaixo_do_minimo_nao_da_bonus():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, min_servico_centavos=5000))
    kw = dict(cliente_id="c", agora=AGORA, profissional_id="p")
    assert conceder_bonus_avaliacao(repo, pedido_id="a", valor_servico_centavos=4999, **kw) == 0
    assert conceder_bonus_avaliacao(repo, pedido_id="b", valor_servico_centavos=5000, **kw) == 50


def test_limite_de_bonus_por_profissional_no_mes():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, max_bonus_por_profissional_mes=1))
    kw = dict(cliente_id="c", agora=AGORA, valor_servico_centavos=10_000)
    assert conceder_bonus_avaliacao(repo, pedido_id="a", profissional_id="p1", **kw) == 50
    assert conceder_bonus_avaliacao(repo, pedido_id="b", profissional_id="p1", **kw) == 0
    assert conceder_bonus_avaliacao(repo, pedido_id="c", profissional_id="p2", **kw) == 50
