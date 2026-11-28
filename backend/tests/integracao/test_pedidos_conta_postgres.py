"""BE-VERIFICA-20.6 no Postgres local: bloquear pela rota de status cancela o pedido futuro,
mantém o em andamento e devolve os quatro campos do resumo."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from trato.api import pedidos_conta

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import limpar
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)


def test_status_bloqueado_devolve_o_resumo_dos_pedidos(pg, equipe, monkeypatch):
    limpar(pg)
    andamento, _ = agendado(pg)
    check_in(pg, andamento)
    futuro, _ = agendado(pg)
    pendente, _ = agendado(pg)
    # Simula a ausência do cliente em análise neste pedido: ele não pode ser cancelado.
    original = pedidos_conta._aguarda_analise
    monkeypatch.setattr(
        pedidos_conta,
        "_aguarda_analise",
        lambda contexto, pedido: pedido.id == pendente or original(contexto, pedido),
    )
    estado = lambda pid: pg.pagto[1].pedidos.obter(pid).estado.value  # noqa: E731
    url = f"/v1/admin/usuarios/{pg.ids['profissional']}/status"
    corpo = {"status": "bloqueado", "motivo": "Conta suspensa para apuração."}
    try:
        r = _post(pg, "adm_a", url, corpo)
        assert r.status_code == 200, r.text
        dados = r.json()
        assert estado(futuro) == "cancelado"
        assert (estado(andamento), estado(pendente)) == ("em_andamento", "agendado")
        assert dados["pedidos_futuros_cancelados"] >= 1
        assert andamento in dados["pedidos_em_andamento_ids"]
        assert dados["pedidos_em_andamento"] == len(dados["pedidos_em_andamento_ids"])
        # Banco compartilhado: outros testes deixam pedidos sem cobrança registrada, que não dá
        # para estornar e por isso também ficam pendentes. Isolado, a lista é só o `pendente`.
        assert pendente in dados["pedidos_futuros_pendentes_ids"]
        assert {futuro, andamento}.isdisjoint(dados["pedidos_futuros_pendentes_ids"])
        assert futuro not in dados["pedidos_em_andamento_ids"]
        pago = pg.pagto[1].ledger.saldos_pedido(futuro, pg.ids["profissional"])
        assert (pago.cliente_pagou, pago.retido) == (0, 0)
        repetido = _post(pg, "adm_a", url, corpo).json()  # já bloqueado: nada novo
        assert repetido["pedidos_futuros_cancelados"] == 0
        assert repetido["pedidos_em_andamento_ids"] == []
    finally:
        limpar(pg)
