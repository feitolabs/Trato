"""BE-68: aditivo só vale pago antes da execução do extra (Termos 6.8) e o bloqueado vê o
próprio pedido cancelado já pago. Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import pytest
from test_cliente_bloqueado_pedido import bloquear, recusado
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401

from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento
from trato.pedidos.estados import Estado

EXTRA = 5_000


def em_andamento(f) -> str:
    pid = f.aceitar()
    f.pagar(pid)
    f.agendar(pid)
    f.iniciar(pid)
    return pid


def propor(f, pid) -> str:
    corpo = {"descricao": "Trocar o registro", "valor_centavos": EXTRA}
    r = f.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo)
    assert r.status_code == 201, r.text
    return r.json()["id"]


def aprovar(f, pid, aid):
    url = f"/v1/pedidos/{pid}/aditivos/{aid}/aprovacao"
    return f.chamar("POST", url, "t-cliente", {"meio": "pix"})


def aprovado(f, pid) -> tuple[str, str]:
    aid = propor(f, pid)
    r = aprovar(f, pid, aid)
    assert r.status_code in (200, 201), r.text
    (cobranca,) = [c for c in f.servico.cobrancas.do_pedido(pid) if c.aditivo_id == aid]
    return aid, cobranca.id


def aviso(f, cobranca_id, instante, evento="evt_aditivo"):
    f.fake.marcar_paga(cobranca_id)
    return f.webhook(
        TipoEvento.PAGAMENTO_CONFIRMADO,
        cobranca_id,
        instante=int(instante.timestamp()),
        evento_id=evento,
    )


def estornos(f, cobranca_id) -> list[int]:
    return [e.valor_centavos for e in f.fake.estornos_da_cobranca(cobranca_id)]


def test_sem_pagar_o_servico_conclui_e_pagamento_posterior_volta_uma_vez(fluxo):
    pid = em_andamento(fluxo)
    aid, cobranca = aprovado(fluxo, pid)
    fluxo.encerrar_execucao(pid)  # o serviço contratado não fica preso pelo aditivo
    assert fluxo.servico.cobrancas.obter(cobranca).status is EstadoCobranca.CANCELADA
    assert ("cancelar_cobranca", cobranca) in fluxo.fake.chamadas
    fluxo.amb.relogio.avancar(minutes=5)
    depois = fluxo.ctx.agora()
    with ThreadPoolExecutor(4) as grupo:
        respostas = list(grupo.map(lambda _: aviso(fluxo, cobranca, depois), range(4)))
    assert {r.status_code for r in respostas} == {200}, [r.text for r in respostas]
    assert estornos(fluxo, cobranca) == [EXTRA]
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR
    assert fluxo.servico.aditivos.obter(aid).estado.value == "aprovado"  # nunca "pago"
    fluxo.concluir(pid)
    assert fluxo.repasse(pid).valor_liquido_centavos == VALOR


def test_pago_antes_do_check_out_com_aviso_atrasado_vale(fluxo):
    pid = em_andamento(fluxo)
    aid, cobranca = aprovado(fluxo, pid)
    pago_em = fluxo.ctx.agora()
    fluxo.amb.relogio.avancar(minutes=5)
    fluxo.encerrar_execucao(pid)
    assert aviso(fluxo, cobranca, pago_em).status_code == 200
    assert estornos(fluxo, cobranca) == []
    assert fluxo.servico.aditivos.obter(aid).estado.value == "pago"
    fluxo.concluir(pid)
    assert fluxo.repasse(pid).valor_liquido_centavos == VALOR + EXTRA


def test_aviso_depois_da_conclusao_devolve(fluxo):
    pid = em_andamento(fluxo)
    _, cobranca = aprovado(fluxo, pid)
    pago_em = fluxo.ctx.agora()
    fluxo.amb.relogio.avancar(minutes=5)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)
    assert aviso(fluxo, cobranca, pago_em).status_code == 200
    assert estornos(fluxo, cobranca) == [EXTRA]
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == 0


def test_depois_do_check_out_nao_se_aprova(fluxo):
    pid = em_andamento(fluxo)
    aid = propor(fluxo, pid)
    fluxo.encerrar_execucao(pid)
    assert aprovar(fluxo, pid, aid).status_code == 409
    assert [c for c in fluxo.servico.cobrancas.do_pedido(pid) if c.aditivo_id] == []


@pytest.mark.parametrize("tipo", ["suspensao", "bloqueio_preventivo"])
def test_bloqueado_ve_o_proprio_cancelado_ja_pago_e_nada_mais(fluxo, tipo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    assert fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti."}).status_code == 200
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO
    aberto = fluxo.chamar("POST", "/v1/pedidos", "t-cliente").json()["id"]
    bloquear(fluxo, tipo)
    lista = fluxo.chamar("GET", "/v1/pedidos", "t-cliente")
    assert lista.status_code == 200 and [p["id"] for p in lista.json()] == [pid], lista.text
    visto = fluxo.chamar("GET", f"/v1/pedidos/{pid}", "t-cliente")
    assert visto.status_code == 200 and visto.json()["acoes_permitidas"] == []
    assert recusado(fluxo.chamar("GET", f"/v1/pedidos/{aberto}", "t-cliente"))
    for quem in ("t-outro-cliente", "t-prof"):
        fluxo.amb.contexto.auth.bloqueados.add(quem)
        assert recusado(fluxo.chamar("GET", f"/v1/pedidos/{pid}", quem)), quem
        assert recusado(fluxo.chamar("GET", "/v1/pedidos", quem)), quem
