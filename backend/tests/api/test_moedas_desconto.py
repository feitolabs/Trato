# ruff: noqa: F811
"""Moedas como desconto no pagamento: o backend escolhe quanto, debita na confirmação e devolve
no estorno total."""

from __future__ import annotations

from dataclasses import replace

from conftest import AGORA, CLIENTE
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api.moedas import (
    ConfigMoedas,
    LancamentoMoeda,
    MoedasEmMemoria,
    calcular_uso_moedas,
    debitar_uso_moedas,
    devolver_uso_moedas,
)
from trato.pagamentos.provedor import TipoEvento

# Orçamento e teto do cliente folgados: estes testes são do desconto em si (o orçamento tem
# os seus em test_moedas_orcamento.py).
_GRANDE = {
    "orcamento_mensal_desconto_centavos": 100_000_000,
    "teto_desconto_cliente_mes_centavos": 100_000_000,
    "teto_diario_desconto_centavos": 100_000_000,
    "dias_liberacao_bonus": 0,
}


def _dar_saldo(repo, moedas, usuario=CLIENTE.id, chave="bonus:teste"):
    repo.lancar(LancamentoMoeda(usuario, "bonus_avaliacao", moedas, chave, AGORA))


def test_uso_respeita_saldo_e_teto_por_servico():
    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, **_GRANDE, valor_moeda_centavos=1, max_desconto_percentual=20)
    )
    _dar_saldo(repo, 5_000)
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (5_000, 5_000)  # tem menos que o teto (20.000)
    _dar_saldo(repo, 50_000, chave="bonus:2")
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=100_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (20_000, 20_000)  # capado em 20% do serviço


def test_uso_zero_quando_desligado_sem_saldo_ou_servico_minusculo():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=False))
    _dar_saldo(repo, 1_000)
    args = {"usuario_id": CLIENTE.id, "agora": AGORA}
    assert calcular_uso_moedas(repo, servico_centavos=100_000, **args).moedas == 0
    ligado = MoedasEmMemoria(ConfigMoedas(ativo=True, **_GRANDE))
    assert calcular_uso_moedas(ligado, servico_centavos=100_000, **args).moedas == 0  # sem saldo
    _dar_saldo(ligado, 1_000)
    assert calcular_uso_moedas(ligado, servico_centavos=100, **args).moedas == 0  # sobra < R$ 1


def test_desconto_nunca_zera_o_servico():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, **_GRANDE, max_desconto_percentual=100))
    _dar_saldo(repo, 1_000_000)
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=5_000, agora=AGORA)
    assert uso.desconto_centavos == 4_900  # sobra R$ 1,00


def test_debito_e_devolucao_sao_idempotentes():
    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, **_GRANDE))
    _dar_saldo(repo, 1_000)
    kw = {
        "usuario_id": CLIENTE.id,
        "cobranca_id": "cob-1",
        "pedido_id": "p",
        "moedas": 400,
        "agora": AGORA,
    }
    assert devolver_uso_moedas(repo, **kw) is False  # sem débito, nada a devolver
    assert debitar_uso_moedas(repo, **kw) is True
    assert debitar_uso_moedas(repo, **kw) is False
    assert repo.saldo(CLIENTE.id, AGORA) == 600
    assert devolver_uso_moedas(repo, **kw) is True
    assert devolver_uso_moedas(repo, **kw) is False
    assert repo.saldo(CLIENTE.id, AGORA) == 1_000


def _ligar(fluxo: Fluxo, saldo: int):
    fluxo.ctx.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True, **_GRANDE, valor_moeda_centavos=1))
    _dar_saldo(fluxo.ctx.moedas, saldo)


def test_pagar_com_moedas_desconta_na_cobranca_e_debita_so_na_confirmacao(fluxo: Fluxo):
    _ligar(fluxo, 5_000)
    pid = fluxo.aceitar()

    previa = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    ).json()
    assert previa["moedas_usadas"] == 5_000 and previa["moedas_saldo"] == 5_000
    assert previa["desconto_centavos"] == 5_000 and previa["total_a_pagar_centavos"] == 95_000
    sem = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento", "t-cliente").json()
    assert sem["moedas_usadas"] == 0 and sem["total_a_pagar_centavos"] == 100_000

    r = fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix", "usar_moedas": True}
    )
    assert r.status_code == 201, r.text
    cob = r.json()
    assert cob["valor_centavos"] == 95_000
    # Criar a cobrança ainda não gasta nada: só a confirmação do pagamento.
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 5_000

    fluxo.fake.marcar_paga(cob["cobranca_id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"]).status_code == 200
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 0
    # Reentrega do webhook não debita de novo.
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"]).status_code == 200
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 0


def test_estorno_total_devolve_as_moedas(fluxo: Fluxo):
    _ligar(fluxo, 5_000)
    pid = fluxo.aceitar()
    cob = fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix", "usar_moedas": True}
    ).json()
    fluxo.fake.marcar_paga(cob["cobranca_id"])
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"])
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 0

    paga = fluxo.servico.cobrancas.obter(cob["cobranca_id"])
    assert paga.moedas_usadas == 5_000
    parcial = replace(paga, estornado_centavos=paga.valor_centavos - 1)
    fluxo.servico._devolver_moedas(fluxo.ctx, parcial)
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 4_999  # parcial: na proporção (13.8)
    total = replace(paga, estornado_centavos=paga.valor_centavos)
    fluxo.servico._devolver_moedas(fluxo.ctx, total)
    fluxo.servico._devolver_moedas(fluxo.ctx, total)  # idempotente
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 5_000


def test_sem_pedir_moedas_nada_muda(fluxo: Fluxo):
    _ligar(fluxo, 5_000)
    pid = fluxo.aceitar()
    cob = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix"}).json()
    assert cob["valor_centavos"] == 100_000
    fluxo.fake.marcar_paga(cob["cobranca_id"])
    fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cob["cobranca_id"])
    assert fluxo.ctx.moedas.saldo(CLIENTE.id, AGORA) == 5_000
