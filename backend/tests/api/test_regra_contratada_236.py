"""BE-VERSAO-CONTRATADA-236 (23.6): vale a regra do aceite, salvo se a vigente for mais
favorável. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta

import pytest
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.admin.rotas_ausencias import _teto_retencao
from trato.api.regra_contratada import regra_do_contrato
from trato.api.repositorios import Contrato
from trato.api.rotas_reagendamento import _antecedencia_horas


def configurar(f, *, arrependimento=None, bps=None, garantia=None, horas=None) -> None:
    config = f.ctx.config
    atual = config.carregar()
    if arrependimento is not None:
        atual = replace(atual, arrependimento_dias=arrependimento)
    if bps is not None:
        atual = replace(atual, ausencia_retencao_max_bps=bps)
    if garantia is not None:
        atual = replace(atual, garantias=replace(atual.garantias, garantia_dias_padrao=garantia))
    config._config = atual
    if horas is not None:
        config.parametros["reagendamento_antecedencia_horas"] = horas


def arrependimento_dias(f, pid) -> int:
    r = f.chamar("GET", f"/v1/pedidos/{pid}/desistencia", "t-cliente").json()
    inicio, ate = (datetime.fromisoformat(r[c]) for c in ("contratado_em", "arrependimento_ate"))
    return (ate.date() - (inicio - timedelta(hours=3)).date()).days


def teto(f, pid) -> int:
    base, maximo = _teto_retencao(f.ctx, f.ctx.pedidos.obter(pid))
    return maximo * 10_000 // base


def contratar(f) -> str:
    pid = f.aceitar()
    f.pagar(pid)
    return pid


@pytest.mark.parametrize(
    ("depois", "esperado"),
    [
        # Piorou depois do aceite: vale o contratado.
        ({"arrependimento": 7, "bps": 3000, "horas": 48, "garantia": 15}, (10, 2000, 24, 90)),
        # Melhorou: vale a nova.
        ({"arrependimento": 20, "bps": 500, "horas": 6, "garantia": 200}, (20, 500, 6, 200)),
    ],
)
def test_vale_o_mais_favoravel_entre_o_aceite_e_o_vigente(fluxo, depois, esperado):
    configurar(fluxo, arrependimento=10, bps=2000, horas=24, garantia=90)
    pid = contratar(fluxo)
    configurar(fluxo, **depois)
    dias, bps, horas, garantia = esperado
    assert arrependimento_dias(fluxo, pid) == dias
    assert teto(fluxo, pid) == bps
    assert _antecedencia_horas(fluxo.ctx, pid) == horas
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    assert fluxo.ctx.garantias.obter_garantia(pid).dias == garantia


def test_contrato_sem_regras_usa_o_vigente_com_os_pisos_e_tetos(fluxo):
    configurar(fluxo, arrependimento=10, bps=1000, horas=12)
    pid = contratar(fluxo)
    contratos = fluxo.ctx.contratos
    contratos._itens[pid] = replace(contratos._itens[pid], regras=None)  # contrato antigo
    configurar(fluxo, arrependimento=3, bps=9000, horas=36)
    assert arrependimento_dias(fluxo, pid) == 7  # piso legal
    assert teto(fluxo, pid) == 3000  # teto de 30%
    assert _antecedencia_horas(fluxo.ctx, pid) == 24  # teto da 7.5


def test_pisos_valem_mesmo_sobre_o_congelado(fluxo):
    pid = contratar(fluxo)
    contratos = fluxo.ctx.contratos
    ruim = {"parametros": {"arrependimento_dias": 2, "ausencia_retencao_max_bps": 9000}}
    contratos._itens[pid] = replace(contratos._itens[pid], regras=ruim)
    configurar(fluxo, arrependimento=3, bps=8000)
    assert arrependimento_dias(fluxo, pid) == 7 and teto(fluxo, pid) == 3000


@pytest.mark.parametrize("valor", [None, True, -1, "24", 1.5])
def test_chave_ausente_ou_invalida_usa_o_vigente(valor):
    parametros = {} if valor is None else {"x": valor}
    contrato = Contrato("p", "o", "pro", 1, regras={"parametros": parametros})
    assert regra_do_contrato(contrato, "x", "menor", 40) == 40
    assert regra_do_contrato(None, "x", "maior", 40) == 40


def test_repetir_o_aceite_nao_troca_o_retrato(fluxo):
    configurar(fluxo, arrependimento=10)
    pid = contratar(fluxo)
    contrato = fluxo.ctx.contratos.obter_do_pedido(pid)
    configurar(fluxo, arrependimento=7)
    fluxo.ctx.contratos.salvar(replace(contrato, regras=None))
    assert fluxo.ctx.contratos.obter_do_pedido(pid).regras == contrato.regras
