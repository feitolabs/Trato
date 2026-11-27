"""BE-GUARDA-TRATINHOS (Termos 13.10 e I.11): guarda por `sem_falta` e devolução, no
restabelecimento, do que venceu desde o encerramento. Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import timedelta

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401
from conftest import CLIENTE
from test_cliente_bloqueado_pedido import bloquear
from test_conta_valores import agendar, lgpd, processar
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.medidas import restabelecer_por_retorno, reverter
from trato.api.moedas import CARTEIRA_CLIENTE, CARTEIRA_PROFISSIONAL, LancamentoMoeda

DIA = timedelta(days=1)


def creditar(f, chave, quantidade, vence_em_dias=None, carteira=CARTEIRA_CLIENTE):
    agora = f.ctx.agora()
    assert f.ctx.moedas.lancar(
        LancamentoMoeda(
            usuario_id=CLIENTE.id,
            tipo="bonus_avaliacao",
            quantidade=quantidade,
            chave_idempotencia=chave,
            criada_em=agora,
            expira_em=agora + vence_em_dias * DIA if vence_em_dias else None,
            carteira=carteira,
        )
    )


def encerrar(f, sem_falta):
    medida = bloquear(f, "encerramento")
    if sem_falta is not None:
        assert f.ctx.medidas.mudar(medida.id, {"sem_falta": sem_falta})
    return replace(medida, sem_falta=sem_falta)


def saldo(f, carteira=CARTEIRA_CLIENTE) -> int:
    return f.ctx.moedas.saldo(CLIENTE.id, f.ctx.agora(), carteira)


def restauracoes(f):
    return [x for x in f.ctx.moedas._itens.values() if x.tipo == "restauracao"]


def cenario(f, sem_falta=True):
    creditar(f, "vence", 120, 10)
    creditar(f, "fica", 50)
    creditar(f, "prof", 30, 10, CARTEIRA_PROFISSIONAL)
    medida = encerrar(f, sem_falta)
    f.amb.relogio.avancar(days=40)
    assert (saldo(f), saldo(f, CARTEIRA_PROFISSIONAL)) == (50, 0)
    return medida


@pytest.mark.parametrize("sem_falta", [True, False, None])
def test_medida_revertida_devolve_o_vencido_uma_vez_por_carteira(fluxo, sem_falta):
    medida = cenario(fluxo, sem_falta)
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    assert not reverter(fluxo.ctx, medida, "eq-mediador")
    assert (saldo(fluxo), saldo(fluxo, CARTEIRA_PROFISSIONAL)) == (170, 30)
    novos = restauracoes(fluxo)
    assert sorted((x.carteira, x.quantidade) for x in novos) == [
        ("cliente", 120),
        ("profissional", 30),
    ]
    assert all(x.chave_idempotencia.endswith(f":{x.carteira}") for x in novos)
    assert all(x.expira_em - x.criada_em >= 30 * DIA for x in novos)


def test_validade_maior_da_configuracao_vale(fluxo):
    repo = fluxo.ctx.moedas
    repo.salvar_config(replace(repo.config(), validade_dias=120))
    medida = cenario(fluxo)
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    assert {x.expira_em - x.criada_em for x in restauracoes(fluxo)} == {120 * DIA}


def test_nada_venceu_nada_e_lancado(fluxo):
    creditar(fluxo, "fica", 50)
    medida = encerrar(fluxo, True)
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    assert restauracoes(fluxo) == [] and saldo(fluxo) == 50


@pytest.mark.parametrize("sem_falta", [True, None])
def test_retorno_aprovado_devolve_mesmo_repetido_e_ao_mesmo_tempo(fluxo, sem_falta):
    medida = cenario(fluxo, sem_falta)
    pedido_em = medida.inicio_em + 30 * DIA
    with ThreadPoolExecutor(4) as grupo:
        feitos = list(
            grupo.map(lambda _: restabelecer_por_retorno(fluxo.ctx, medida.id, pedido_em), range(4))
        )
    assert sum(feitos) == 150 and len(restauracoes(fluxo)) == 2
    assert fluxo.ctx.medidas.obter(medida.id).sem_falta is True


@pytest.mark.parametrize("sem_falta,dias", [(False, 30), (True, 91)])
def test_retorno_por_falta_ou_fora_dos_90_dias_nao_devolve(fluxo, sem_falta, dias):
    medida = cenario(fluxo, sem_falta)
    assert restabelecer_por_retorno(fluxo.ctx, medida.id, medida.inicio_em + dias * DIA) == 0
    assert restauracoes(fluxo) == []


def test_banco_sem_a_migration_nao_devolve_nem_quebra(fluxo):
    medida = cenario(fluxo)
    fluxo.ctx.moedas.restauracao_disponivel = lambda: False
    assert restabelecer_por_retorno(fluxo.ctx, medida.id, medida.inicio_em + DIA) == 0
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    assert restauracoes(fluxo) == []


@pytest.mark.parametrize("sem_falta,fica", [(True, 50), (None, 50), (False, 0)])
def test_guarda_e_baixa_seguem_sem_falta(fluxo, sem_falta, fica):
    s = lgpd(fluxo)
    creditar(fluxo, "fica", 50)
    agendar(fluxo, s)
    encerrar(fluxo, sem_falta)
    processar(fluxo, s)
    assert saldo(fluxo) == fica


def test_painel_grava_e_devolve_sem_falta_e_recusa_combinacao_invalida(adm):
    corpo = {
        "usuario_id": CLIENTE.id,
        "tipo": "encerramento",
        "motivo": "Conta encerrada por decisão da plataforma.",
        "clausulas": ["20.8"],
    }
    adm.contexto.usuarios.garantir(CLIENTE.id)
    h = cab(token_de("mediador"))
    for extra in (
        {"sem_falta": True, "infracao_grave": True},
        {"tipo": "aviso", "sem_falta": True},
    ):
        r = adm.cliente.post("/v1/admin/medidas", json=corpo | extra, headers=h)
        assert r.status_code == 422 and r.json()["codigo"] == "sem_falta_invalida", r.text
    r = adm.cliente.post("/v1/admin/medidas", json=corpo | {"sem_falta": True}, headers=h)
    assert r.status_code in (200, 201), r.text
    assert r.json()["sem_falta"] is True
