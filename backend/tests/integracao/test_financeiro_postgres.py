"""Financeiro do painel contra o Postgres LOCAL (pgserver): pagamentos e conciliação.

Cobre o que a memória não pega: o id do lançamento no ledger (hex) e o da auditoria (uuid com
hífens) são o mesmo lançamento, e o ledger inteiro é lido numa consulta só.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

from trato.financeiro.ledger import Livro, registrar_cobranca

from .test_dinheiro_postgres import VALOR, contratar, pagar_pelo_webhook

pytestmark = pytest.mark.integracao

BASE = "/v1/admin"


def _cobranca_sem_pagamento(c) -> str:
    """Pedido contratado com cobrança no ledger, mas sem a prova de pagamento: divergência."""
    pedido_id = contratar(c)
    livro = Livro()
    registrar_cobranca(livro, pedido_id, 12_345, f"teste-div/{pedido_id}", datetime.now(UTC))
    c.contexto.ledger.lancar_varios(livro.lancamentos)
    return pedido_id


def _do_pedido(c, pedido_id: str) -> dict:
    itens = c.cliente.get(f"{BASE}/pagamentos?limite=100", headers=c.token("equipe2")).json()
    return next(i for i in itens["itens"] if i["pedido_id"] == pedido_id)


def test_pagamento_pelo_webhook_aparece_conferido_com_taxa(cenario):
    pedido_id = contratar(cenario)
    assert pagar_pelo_webhook(cenario, pedido_id).status_code == 200

    item = _do_pedido(cenario, pedido_id)

    assert item["valor_centavos"] == VALOR
    assert item["divergente"] is False
    assert item["referencia_provedor"] == f"pi_{pedido_id[:8]}"
    assert item["taxa_trato_centavos"] == 0  # o webhook antigo não separa a taxa na cobrança


def test_conciliar_no_banco_tira_a_divergencia_de_vez(cenario):
    pedido_id = _cobranca_sem_pagamento(cenario)
    item = _do_pedido(cenario, pedido_id)
    assert item["divergente"] is True

    r = cenario.cliente.post(
        f"{BASE}/divergencias/{item['lancamento_id']}/conciliar",
        json={"motivo": "Cobrança de teste conferida no extrato"},
        headers=cenario.token("equipe2"),
    )

    assert r.status_code == 204, r.text
    # Antes: a auditoria devolvia o uuid com hífens e o ledger sem; a divergência voltava.
    assert _do_pedido(cenario, pedido_id)["divergente"] is False
    de_novo = cenario.cliente.post(
        f"{BASE}/divergencias/{item['lancamento_id']}/conciliar",
        json={"motivo": "Cobrança de teste conferida no extrato"},
        headers=cenario.token("equipe2"),
    )
    assert de_novo.status_code == 409


def test_ledger_inteiro_numa_consulta_igual_ao_lido_por_pedido(cenario):
    a = contratar(cenario)
    pagar_pelo_webhook(cenario, a)
    b = _cobranca_sem_pagamento(cenario)

    todos = cenario.contexto.ledger.lancamentos()

    for pedido_id in (a, b):
        do_pedido = cenario.contexto.ledger.lancamentos(pedido_id)
        assert do_pedido
        assert [i for i in todos if i.pedido_id == pedido_id] == list(do_pedido)
