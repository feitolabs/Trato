"""BE-ORFAO no Postgres local: o aviso de estorno espera a fila do pedido e a devolução do
órfão não tira nada da custódia paga por outra cobrança."""

from __future__ import annotations

import threading

from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.provedor.base import TipoEvento

from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    cobrar_ok,
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

SITUACAO = (
    "select status, estornado_centavos from public.pagamentos where stripe_payment_intent_id = %s"
)


def test_orfao_e_aviso_juntos_com_a_fila_do_pedido(pg):  # noqa: F811
    contexto, servico = pg.pagto[1], pg.pagto[2]
    fake = servico.provedor
    pid = pedido_aceito(pg)
    velha = cobrar_ok(pg, pid)
    nova = cobrar_ok(pg, pid, "cartao")
    assert nova["id"] != velha["id"]
    assert ("cancelar_cobranca", velha["id"]) in fake.chamadas
    fake.marcar_paga(nova["id"])
    r = webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, nova["id"])
    assert r.status_code == 200, r.text
    antes = contexto.ledger.saldo_da_conta(CUSTODIA, pid)
    assert antes > 0
    fake.marcar_paga(velha["id"])

    respostas = []

    def avisar(evento):
        respostas.append(webhook(pg, TipoEvento.ESTORNO_CONFIRMADO, velha["id"], evento_id=evento))

    # Estorno já feito no provedor e devolução ainda sem gravar, com o pedido travado.
    fake.estornar(velha["id"], None, f"orfao/{velha['id']}")
    primeiro = threading.Thread(target=avisar, args=("evt_orf_a",))
    with contexto.transacao():
        contexto.pedidos.travar(pid)
        primeiro.start()
        primeiro.join(1.0)
        assert primeiro.is_alive()
    primeiro.join(20)
    tarefas = [
        threading.Thread(target=avisar, args=("evt_orf_b",)),
        threading.Thread(
            target=lambda: respostas.append(
                webhook(pg, TipoEvento.PAGAMENTO_CONFIRMADO, velha["id"], evento_id="evt_orf_p")
            )
        ),
    ]
    for t in tarefas:
        t.start()
    for t in tarefas:
        t.join()
    assert {r.status_code for r in respostas} == {200}, [r.text for r in respostas]
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == antes
    assert linhas(pg, SITUACAO, (velha["id"],)) == [("reembolsado", velha["valor_centavos"])]
    assert linhas(pg, SITUACAO, (nova["id"],)) == [("confirmado", 0)]
    assert len(fake.estornos_da_cobranca(velha["id"])) == 1
