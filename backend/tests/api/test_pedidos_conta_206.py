"""BE-PEDIDOS-FUTUROS-20.6: suspensão e encerramento cancelam os pedidos futuros sem custo, com
reembolso integral; o serviço em andamento fica. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from conftest import CLIENTE, PROFISSIONAL, cab
from test_cliente_bloqueado_pedido import bloquear
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_pessoa_diferente import agendado, estado
from test_termos_m2_dinheiro import custodia, total_estornado

from trato.api.medidas import iniciar_agendadas
from trato.api.pedidos_conta import resumo, tratar_pedidos
from trato.api.recorrencias import ST_ATIVA, ST_PAUSADA, V_CANCELADA, Recorrencia
from trato.notificacoes.eventos import MODELOS, Evento
from trato.pedidos.estados import Acao, Estado


class Avisos:
    def __init__(self):
        self.enviados = []

    def notificar(self, evento, usuario, **kw):
        self.enviados.append((evento, usuario, kw))

    def cancelados(self):
        return [(u, k) for e, u, k in self.enviados if e is Evento.PEDIDO_CANCELADO_CONTA]

    def series(self):
        return [u for e, u, _ in self.enviados if e is Evento.SERIE_PAUSADA_CONTA]


def cancelamentos(f, pid):
    return [e for e in f.ctx.pedidos.eventos(pid) if e.acao is Acao.CANCELAR_MEDIDA_CONTA]


@pytest.mark.parametrize(
    ("tipo", "token", "suspenso", "outra"),
    [
        ("suspensao", "t-prof", PROFISSIONAL.id, CLIENTE.id),
        ("encerramento", "t-cliente", CLIENTE.id, PROFISSIONAL.id),
    ],
)
def test_pedido_pago_e_cancelado_com_reembolso_integral_e_aviso(
    fluxo, tipo, token, suspenso, outra
):
    pid, cobranca = agendado(fluxo)
    avisos = fluxo.ctx.extras["notificador"] = Avisos()
    medida = bloquear(fluxo, tipo, token, suspenso)
    assert estado(fluxo, pid) is Estado.CANCELADO and custodia(fluxo, pid) == 0
    assert total_estornado(fluxo, cobranca) == VALOR
    ((usuario, kw),) = avisos.cancelados()
    assert usuario == outra and "conta da outra parte" in kw["corpo"]
    r = resumo(fluxo.ctx, suspenso, medida.inicio_em)
    assert (r.futuros_cancelados, r.em_andamento, r.futuros_pendentes) == (1, (), ())


def test_repetir_e_concorrer_nao_estorna_duas_vezes(fluxo):
    pid, cobranca = agendado(fluxo)
    with ThreadPoolExecutor(4) as grupo:
        list(grupo.map(lambda _: tratar_pedidos(fluxo.ctx, PROFISSIONAL.id), range(4)))
    assert tratar_pedidos(fluxo.ctx, PROFISSIONAL.id) == 0
    assert len(cancelamentos(fluxo, pid)) == 1
    assert total_estornado(fluxo, cobranca) == VALOR and custodia(fluxo, pid) == 0


def test_em_andamento_fica_intacto_e_aparece_como_pendente(fluxo):
    pid, cobranca = agendado(fluxo)
    fluxo.iniciar(pid)
    medida = bloquear(fluxo, "suspensao", "t-prof", PROFISSIONAL.id)
    assert estado(fluxo, pid) is Estado.EM_ANDAMENTO and custodia(fluxo, pid) == VALOR
    assert total_estornado(fluxo, cobranca) == 0
    r = resumo(fluxo.ctx, PROFISSIONAL.id, medida.inicio_em)
    assert (r.futuros_cancelados, r.em_andamento) == (0, (pid,))


def test_bloqueio_preventivo_nao_cancela(fluxo):
    pid, _ = agendado(fluxo)
    bloquear(fluxo, "bloqueio_preventivo", "t-prof", PROFISSIONAL.id)
    assert estado(fluxo, pid) is Estado.AGENDADO and custodia(fluxo, pid) == VALOR


def test_recorrencia_ativa_e_pausada_com_aviso(fluxo):
    agora = fluxo.ctx.agora()
    serie = fluxo.ctx.recorrencias.criar(
        Recorrencia(
            id="rec-206",
            pedido_origem_id="ped-origem",
            cliente_id=CLIENTE.id,
            profissional_id=PROFISSIONAL.id,
            categoria_id="pintura",
            frequencia="semanal",
            valor_centavos=VALOR,
            status=ST_ATIVA,
            proposto_por=CLIENTE.id,
            criado_em=agora,
            proxima_visita_em=agora + timedelta(days=7),
        )
    )
    # Visita ainda sem orçamento: o profissional da série não é parte do pedido aberto.
    pid = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    visita = fluxo.ctx.recorrencias.reservar_visita(serie.id, serie.proxima_visita_em, agora)
    fluxo.ctx.recorrencias.vincular_pedido(visita.id, pid)
    avisos = fluxo.ctx.extras["notificador"] = Avisos()
    medida = bloquear(fluxo, "suspensao", "t-prof", PROFISSIONAL.id)
    assert fluxo.ctx.recorrencias.obter(serie.id).status == ST_PAUSADA
    assert estado(fluxo, pid) is Estado.CANCELADO
    assert fluxo.ctx.recorrencias.obter_visita(visita.id).status == V_CANCELADA
    assert avisos.series() == [CLIENTE.id]
    assert [u for u, _ in avisos.cancelados()] == [CLIENTE.id]  # só a visita
    assert MODELOS[Evento.SERIE_PAUSADA_CONTA].titulo == "Serviço recorrente pausado"
    assert resumo(fluxo.ctx, PROFISSIONAL.id, medida.inicio_em).futuros_cancelados == 1


def test_agendador_recupera_o_que_falhou_ao_aplicar(fluxo, monkeypatch):
    pid, cobranca = agendado(fluxo)
    with monkeypatch.context() as m:
        m.setattr("trato.api.medidas.tratar_pedidos", lambda *_: 0)
        bloquear(fluxo, "suspensao", "t-prof", PROFISSIONAL.id)
    assert estado(fluxo, pid) is Estado.AGENDADO
    fluxo.ctx.medidas.status[PROFISSIONAL.id] = "bloqueado"
    for _ in range(2):
        iniciar_agendadas(fluxo.ctx, fluxo.ctx.agora())
    assert estado(fluxo, pid) is Estado.CANCELADO and len(cancelamentos(fluxo, pid)) == 1
    assert total_estornado(fluxo, cobranca) == VALOR


def test_detalhe_da_medida_no_painel_traz_o_resumo(fluxo):
    com_equipe(fluxo.amb)
    pid, _ = agendado(fluxo)
    medida = bloquear(fluxo, "suspensao", "t-prof", PROFISSIONAL.id)
    r = fluxo.http.get(f"/v1/admin/medidas/{medida.id}", headers=cab("t-mediador"))
    assert r.status_code == 200, r.text
    assert r.json()["pedidos_futuros_cancelados"] == 1
    assert r.json()["pedidos_em_andamento"] == 0
    assert r.json()["pedidos_em_andamento_ids"] == []
    assert estado(fluxo, pid) is Estado.CANCELADO
