"""BE-SEG-LOTE: aviso de liquidação (payout) depois de um reembolso direto parcial."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from trato.financeiro.ledger import Livro, TipoLancamento, a_liberar, liberado, liberar
from trato.pagamentos.provedor import TipoEvento

from .test_compensacao_postgres import concluido, zerar
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    migrations_novas,
    pg,
    webhook,
)

pytestmark = pytest.mark.integracao

LIBERADO = VALOR_ORCAMENTO // 3
DEVOLVIDO = VALOR_ORCAMENTO // 4
RESTA = VALOR_ORCAMENTO - LIBERADO - DEVOLVIDO


@pytest.fixture
def amb(pg, equipe):
    zerar(pg)
    yield pg
    zerar(pg)


def cenario_parcial(c):
    """Concluído (repasse agendado do valor inteiro), liberação parcial e reembolso direto."""
    contexto = c.pagto[1]
    pid = concluido(c)
    prof = contexto.pedidos.obter(pid).profissional_id
    (repasse,) = contexto.repasses.do_pedido(pid)
    assert repasse.valor_liquido_centavos == VALOR_ORCAMENTO
    livro = Livro()
    livro.lancar_varios(list(contexto.ledger.lancamentos(pid)))
    parte = liberar(livro, pid, prof, f"teste:{pid}:lib", datetime.now(UTC), LIBERADO)
    contexto.ledger.lancar_varios([parte])
    (cobranca,) = c.pagto[2].cobrancas.do_pedido(pid)
    r = webhook(
        c,
        TipoEvento.ESTORNO_CONFIRMADO,
        cobranca.id,
        evento_id=f"evt_{uuid.uuid4().hex}",
        valor_centavos=DEVOLVIDO,
    )
    assert r.status_code == 200, r.text
    tipos = [i.tipo for i in contexto.ledger.lancamentos(pid)]
    assert TipoLancamento.REEMBOLSO in tipos
    return pid, prof, cobranca.id, repasse


def saldos(c, pid, prof):
    ledger = c.pagto[1].ledger
    return (ledger.saldo_da_conta(a_liberar(prof), pid), ledger.saldo_da_conta(liberado(prof), pid))


@pytest.mark.parametrize("pago", [VALOR_ORCAMENTO, RESTA])
def test_liquidacao_apos_reembolso_direto_nao_lanca_o_que_nao_existe(amb, pago):
    """O registro de repasse é imutável e ainda diz o valor antigo: nem o valor dele (acima do
    saldo) nem o saldo do livro (diferente do registro) são lançados. Vai para revisão, com
    2xx, e o reenvio não muda nada."""
    c = amb
    contexto = c.pagto[1]
    pid, prof, cobranca, repasse = cenario_parcial(c)
    assert saldos(c, pid, prof) == (RESTA, LIBERADO)
    antes = contexto.ledger.lancamentos(pid)
    evento = f"evt_{uuid.uuid4().hex}"
    for _ in range(2):
        r = webhook(
            c,
            TipoEvento.LIQUIDACAO,
            cobranca,
            evento_id=evento,
            repasse_id=repasse.id,
            objeto_id=f"po_{evento}",
            valor_centavos=pago,
        )
        assert r.status_code == 200, r.text
    assert contexto.ledger.lancamentos(pid) == antes
    assert saldos(c, pid, prof) == (RESTA, LIBERADO)
    (depois,) = contexto.repasses.do_pedido(pid)
    assert depois.status == "agendado" and depois.lancamento_id is None
    revisoes = [m for e, m in contexto.eventos_webhook.em_revisao() if e.evento_id == evento]
    assert len(revisoes) == 1 and repasse.id in revisoes[0]
