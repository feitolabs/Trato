"""Reagendamento no Postgres: tabela, índice de uma pendente só e janela nova no agendamento."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from trato.pedidos import estados
from trato.pedidos.estados import Ator, Papel, ProvaPagamento

from .test_fluxo_postgres import abrir_pedido, acao, agora, enviar_orcamento
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao


def _agendado(c) -> str:
    pedido_id = abrir_pedido(c)
    orcamento_id = enviar_orcamento(c, pedido_id)
    assert (
        acao(
            c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id}
        ).status_code
        == 200
    )
    t = estados.transicionar(
        c.contexto.pedidos.obter(pedido_id),
        estados.Acao.CONFIRMAR_PAGAMENTO,
        Ator(Papel.SISTEMA, "sistema"),
        agora(),
        ProvaPagamento(f"pi_{uuid.uuid4().hex[:8]}"),
    )
    c.contexto.pedidos.salvar(t.pedido, t.evento)
    inicio = agora() + timedelta(days=2)
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    r = acao(c, "profissional", pedido_id, "confirmar_agenda", {"janela": janela})
    assert r.status_code == 200, r.text
    return pedido_id


def test_reagendamento_completo_no_postgres(cenario):
    c = cenario
    pedido_id = _agendado(c)
    url = f"/v1/pedidos/{pedido_id}/reagendamentos"
    novo = agora() + timedelta(days=5)
    corpo = {
        "nova_janela_inicio": novo.isoformat(),
        "nova_janela_fim": (novo + timedelta(hours=2)).isoformat(),
        "motivo": "Imprevisto",
    }

    r = post(c, url, "cliente", corpo)
    assert r.status_code == 201, r.text
    proposta = r.json()
    # índice único parcial: a segunda pendente vira 409
    assert post(c, url, "profissional", corpo).status_code == 409
    # quem propôs não aceita; a outra parte aceita
    base = f"{url}/{proposta['id']}"
    assert post(c, f"{base}/aceitar", "cliente").status_code == 403
    ok = post(c, f"{base}/aceitar", "profissional")
    assert ok.status_code == 200, ok.text
    assert ok.json()["status"] == "aceito"
    assert post(c, f"{base}/recusar", "profissional").status_code == 409

    lista = get(c, url, "cliente").json()
    assert [i["status"] for i in lista] == ["aceito"]
    janela = c.contexto.pedidos.obter(pedido_id).janela
    assert janela.inicio == novo
    with c.local.admin() as con:
        ag = con.execute(
            "select a.janela_inicio from public.agendamentos a "
            "join public.contratos k on k.id = a.contrato_id "
            "where k.pedido_id = %s and a.status <> 'remarcado'",
            (pedido_id,),
        ).fetchone()
    assert ag[0] == novo
