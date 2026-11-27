"""BE-AUSENCIA-BLOQ (Termos 20.6): cliente com a conta bloqueada não sofre retenção por
ausência. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import pytest
from test_ausencia_cliente import (
    LONGE,
    RETENCAO,
    estado,
    painel,
    registrado,
    remarcado_para_longe,
)
from test_cliente_bloqueado_pedido import TIPOS, bloquear
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_provas_ausencia import com_retencao, confirmar
from test_termos_m2_dinheiro import agendador, custodia, total_estornado

from trato.api.medidas import reverter
from trato.financeiro.ledger import a_liberar
from trato.pedidos.estados import Estado


def retido_ao_profissional(f, pid) -> int:
    prof = f.ctx.pedidos.obter(pid).profissional_id
    return f.ctx.ledger.saldo_da_conta(a_liberar(prof), pid)


def sem_prazo_para_justificar(f) -> None:
    f.amb.relogio.avancar(hours=25)


@pytest.mark.parametrize("tipo", TIPOS)
def test_analista_nao_propoe_retencao_e_sem_ela_o_valor_volta_inteiro(fluxo, tipo):
    pid, cobranca = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)  # registrar a ausência não move dinheiro
    bloquear(fluxo, tipo)
    sem_prazo_para_justificar(fluxo)
    antes = fluxo.tipos(pid)
    r = painel(fluxo, pid, **RETENCAO)
    assert r.status_code == 409 and "bloqueada" in r.json()["detail"], r.text
    assert estado(fluxo, pid) is Estado.AGENDADO and fluxo.tipos(pid) == antes
    assert fluxo.ctx.cancelamentos.do_pedido(pid) is None
    r = painel(fluxo, pid)
    assert r.status_code == 200, r.text
    assert estado(fluxo, pid) is Estado.CANCELADO and custodia(fluxo, pid) == 0
    assert retido_ao_profissional(fluxo, pid) == 0
    assert total_estornado(fluxo, cobranca) == VALOR
    lancamentos = fluxo.tipos(pid)
    assert painel(fluxo, pid).status_code == 409  # repetir não move de novo
    assert fluxo.tipos(pid) == lancamentos


def test_proposta_anterior_ao_bloqueio_so_confirma_sem_retencao(fluxo):
    pid, _, _ = com_retencao(fluxo)
    bloquear(fluxo)
    fluxo.amb.relogio.avancar(days=20)  # o prazo de contestação já passou
    antes = fluxo.tipos(pid)
    r = confirmar(fluxo, pid)
    assert r.status_code == 409 and "retirar_retencao" in r.json()["detail"], r.text
    agendador(fluxo).rodar_uma_vez()  # a rotina não confirma nem cobra a proposta
    assert estado(fluxo, pid) is Estado.AGENDADO and fluxo.tipos(pid) == antes
    r = confirmar(fluxo, pid, retirar_retencao=True)
    assert r.status_code == 200, r.text
    assert r.json()["cancelamento_status"] == "cancelado_sem_retencao"
    assert estado(fluxo, pid) is Estado.CANCELADO
    assert custodia(fluxo, pid) == 0 and retido_ao_profissional(fluxo, pid) == 0
    lancamentos = fluxo.tipos(pid)
    assert confirmar(fluxo, pid, retirar_retencao=True).status_code == 409
    agendador(fluxo).rodar_uma_vez()
    assert fluxo.tipos(pid) == lancamentos


def test_desbloqueado_volta_a_regra_de_sempre(fluxo):
    pid, _, _ = com_retencao(fluxo)
    medida = bloquear(fluxo)
    fluxo.amb.relogio.agora += timedelta(days=20)
    assert confirmar(fluxo, pid).status_code == 409
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    r = confirmar(fluxo, pid)
    assert r.status_code == 200, r.text
    assert retido_ao_profissional(fluxo, pid) == RETENCAO["retencao_centavos"]
