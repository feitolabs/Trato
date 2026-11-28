"""BE-FECHA-223-610-75: expiração do pedido na falha (22.3), estorno visível ao cliente
bloqueado (6.10) e o aviso da 7.5 conforme quem propôs."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA
from test_agendador import montar
from test_cliente_bloqueado_pedido import bloquear
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_indisponibilidade_223 import acao_de, falha
from test_pessoa_diferente import agendado, relatar

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.repositorios import DadosPedido
from trato.pedidos.estados import Acao, Estado

H = timedelta(hours=1)
D = timedelta(days=1)


def expirar(amb, **kw) -> None:
    ExecutorContexto(amb.contexto, **kw).executar(
        acao_de("ped-1", Acao.EXPIRAR_PEDIDO), amb.relogio.agora
    )


def aberto(amb, **campos):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None, **campos)
    return lambda: amb.contexto.pedidos.obter("ped-1").estado


def test_pedido_sem_orcamento_expira_so_depois_do_prazo_prorrogado(amb):
    estado = aberto(amb, aberto_em=AGORA - 4 * D)  # prazo: 3 dias
    janela = falha(amb.contexto, AGORA - 3 * D)  # ativa
    with pytest.raises(Adiada, match="indisponibilidade"):
        expirar(amb)
    amb.contexto.indisponibilidades.encerrar(janela.id, AGORA - D, "eq-admin")  # +2 dias
    with pytest.raises(Adiada):
        expirar(amb)
    assert estado() is Estado.ABERTO
    amb.relogio.avancar(days=1, seconds=1)
    expirar(amb)
    expirar(amb)
    assert estado() is Estado.CANCELADO
    assert len(amb.contexto.pedidos.eventos("ped-1")) == 1


def test_falha_do_pagamento_nao_adia_o_pedido(amb):
    estado = aberto(amb, aberto_em=AGORA - 4 * D)
    falha(amb.contexto, AGORA - 3 * D, origem="pagamento")
    expirar(amb)
    assert estado() is Estado.CANCELADO


@pytest.mark.parametrize("urgente", [False, True])
def test_prazo_urgente_tambem_e_prorrogado(amb, urgente):
    estado = aberto(amb, aberto_em=AGORA - 8 * H)
    amb.contexto.pedidos._dados["ped-1"] = DadosPedido(
        "cat-1", "cid", "Vazamento", "Cozinha", urgente=urgente
    )
    falha(amb.contexto, AGORA - 7 * H, AGORA - 4 * H)  # 3 h
    if not urgente:
        expirar(amb, validade_urgente=6 * H)  # prazo normal (3 dias) ainda correndo
        assert estado() is Estado.ABERTO
        return
    with pytest.raises(Adiada):  # 6 h + 3 h de falha: vence em 1 h
        expirar(amb, validade_urgente=6 * H)
    amb.relogio.avancar(hours=1, seconds=1)
    expirar(amb, validade_urgente=6 * H)
    assert estado() is Estado.CANCELADO


def test_agendador_nao_expira_durante_a_falha_ativa(amb):
    estado = aberto(amb, aberto_em=AGORA - 10 * D)
    amb.contexto.orcamentos._itens.clear()  # com orçamento o pedido não expira
    amb.contexto.orcamentos._detalhes.clear()
    janela = falha(amb.contexto, AGORA - 9 * D)
    agendador, _, _ = montar(amb)
    agendador.rodar_uma_vez()
    assert estado() is Estado.ABERTO
    amb.contexto.indisponibilidades.encerrar(janela.id, AGORA - 8 * D, "eq-admin")
    agendador.rodar_uma_vez()
    assert estado() is Estado.CANCELADO


def cobrancas(f, pid, quem="t-cliente"):
    return f.chamar("GET", f"/v1/pedidos/{pid}/cobrancas", quem)


def test_cliente_bloqueado_ve_o_estorno_do_proprio_pedido_e_nada_mais(fluxo):
    pid, _ = agendado(fluxo)
    antes = cobrancas(fluxo, pid).json()[0]
    assert antes["estorno_valor_centavos"] is None and antes["estorno_solicitado_em"] is None
    assert relatar(fluxo, pid).json()["cancelado"] is True
    nao_contratado = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    bloquear(fluxo, "bloqueio_preventivo")
    r = cobrancas(fluxo, pid)
    assert r.status_code == 200, r.text
    (item,) = r.json()
    assert item["estorno_valor_centavos"] == VALOR and item["estorno_status"]
    assert item["estorno_solicitado_em"] and item["instrucao"] is None
    assert (item["estorno_enviado_em"] is not None) == (item["estorno_status"] == "concluido")
    for alvo in (nao_contratado, "nao-existe"):
        r = cobrancas(fluxo, alvo)
        assert r.status_code == 403 and r.json()["codigo"] == "conta_bloqueada", r.text
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "pix"})
    assert r.status_code == 403
    fluxo.amb.contexto.auth.bloqueados.add("t-prof")
    assert cobrancas(fluxo, pid, "t-prof").status_code == 403  # profissional bloqueado não
    assert cobrancas(fluxo, pid, "t-outro-cliente").status_code == 404
