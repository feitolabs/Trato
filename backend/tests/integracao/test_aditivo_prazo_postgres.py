"""BE-68 no Postgres local (Termos 6.8): a cobrança do aditivo encerrada no check-out ainda
vale quando o dinheiro entrou antes dele, e volta quando entrou depois."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.pagamentos.provedor.base import TipoEvento

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
    webhook,
)

SITUACAO = (
    "select status, estornado_centavos from public.pagamentos where stripe_payment_intent_id = %s"
)


@pytest.mark.parametrize("antes", [True, False])
def test_aditivo_e_check_out(pg, antes):  # noqa: F811
    http, contexto, servico = pg.pagto
    pid, _ = agendado(pg)
    check_in(pg, pid)
    pedido = contexto.pedidos.obter(pid)
    aditivo = servico.propor_aditivo(contexto, pedido, "Trocar o registro", 5_000)
    _, cobranca = servico.aprovar_aditivo(contexto, pedido, aditivo.id, _pix())
    pago_em = datetime.now(UTC) - timedelta(seconds=2)
    visto = http.get(f"/v1/pedidos/{pid}", headers=pg.token("cliente")).json()
    saida = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    r = _post(pg, "profissional", f"/v1/pedidos/{pid}/acoes/fazer_check_out", {"prova": saida})
    assert r.status_code == 200, r.text
    assert linhas(pg, SITUACAO, (cobranca.id,)) == [("expirado", 0)]
    servico.provedor.marcar_paga(cobranca.id)
    instante = pago_em if antes else datetime.now(UTC) + timedelta(seconds=60)
    for n in (1, 2):
        r = webhook(
            pg,
            TipoEvento.PAGAMENTO_CONFIRMADO,
            cobranca.id,
            instante=int(instante.timestamp()),
            evento_id=f"evt_ad_{pid}_{n}",
        )
        assert r.status_code == 200, r.text
    esperado = ("confirmado", 0) if antes else ("reembolsado", 5_000)
    assert linhas(pg, SITUACAO, (cobranca.id,)) == [esperado]
    devolvidos = [e.valor_centavos for e in servico.provedor.estornos_da_cobranca(cobranca.id)]
    assert devolvidos == ([] if antes else [5_000])


def _pix():
    from trato.pagamentos.custo import MeioPagamento

    return MeioPagamento.PIX
