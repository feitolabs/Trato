"""BE-95-96 no Postgres local (Termos 9.5): o banco aceita o cancelamento por pessoa diferente
e relatos ao mesmo tempo geram um reembolso só."""

from __future__ import annotations

import threading

from trato.financeiro.ledger import CUSTODIA

from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado, ordens
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_incidentes_postgres import publicado  # noqa: F401 - fixtures
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)


def relatar(c, pid):
    url = f"/v1/pedidos/{pid}/seguranca/pessoa-diferente"
    return c.pagto[0].post(url, json={}, headers=c.token("cliente"))


def test_relatos_juntos_cancelam_e_estornam_uma_vez(publicado):  # noqa: F811
    c = publicado
    contexto = c.pagto[1]
    pid, _ = agendado(c)
    pago = contexto.ledger.saldo_da_conta(CUSTODIA, pid)
    assert pago > 0
    respostas = []
    tarefas = [threading.Thread(target=lambda: respostas.append(relatar(c, pid))) for _ in range(4)]
    for t in tarefas:
        t.start()
    for t in tarefas:
        t.join()
    assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
    assert all(r.json()["cancelado"] for r in respostas)
    assert contexto.pedidos.obter(pid).estado.value == "cancelado"
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert len(ordens(c, pid)) == 1
    sql = "select count(*) from public.incidentes_seguranca where pedido_id = %s"
    assert linhas(c, sql, (pid,)) == [(1,)]


def test_depois_do_check_in_o_valor_fica_retido(publicado):  # noqa: F811
    c = publicado
    contexto = c.pagto[1]
    pid, _ = agendado(c)
    check_in(c, pid)
    r = relatar(c, pid)
    assert r.status_code == 200 and r.json()["cancelado"] is False, r.text
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) > 0
    assert not ordens(c, pid)
