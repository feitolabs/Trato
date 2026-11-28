"""BE-SALDO-ESTORNO no Postgres local: o banco aceita o reembolso direto do saldo retido depois
de uma liberação parcial (disputa e webhooks) e a compensação da disputa não devolve duas vezes."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from trato.financeiro.ledger import (
    CUSTODIA,
    Livro,
    TipoLancamento,
    a_liberar,
    liberado,
    liberar,
    repartir_custodia,
)
from trato.pagamentos.provedor import TipoEvento

from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_compensacao_postgres import zerar
from .test_disputa_painel_postgres import decidir, devolvido, equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    _aplicar,
    linhas,
    migrations_novas,
    pg,
    webhook,
)

pytestmark = pytest.mark.integracao

LIBERADO = VALOR_ORCAMENTO // 3
RETIDO = VALOR_ORCAMENTO - LIBERADO


@pytest.fixture
def amb(pg, equipe):
    zerar(pg)
    yield pg
    zerar(pg)


def pago_com_liberacao_parcial(c) -> tuple[str, str, str]:
    """Pago; uma parte já liberada ao profissional e o resto ainda na custódia."""
    contexto = c.pagto[1]
    pid, cobranca, _ = pago_e_agendado(c)
    prof = contexto.pedidos.obter(pid).profissional_id
    livro = Livro()
    livro.lancar_varios(list(contexto.ledger.lancamentos(pid)))
    antes = len(livro.lancamentos)
    agora = datetime.now(UTC)
    repartir_custodia(livro, pid, prof, 0, f"teste:{pid}:rep", agora, LIBERADO)
    liberar(livro, pid, prof, f"teste:{pid}:lib", agora)
    contexto.ledger.lancar_varios(list(livro.lancamentos[antes:]))
    return pid, cobranca, prof


def saldos(c, pid, prof) -> tuple[int, int, int]:
    ledger = c.pagto[1].ledger
    return tuple(ledger.saldo_da_conta(x, pid) for x in (CUSTODIA, a_liberar(prof), liberado(prof)))


def reembolsos(c, pid) -> list[int]:
    return [
        i.valor for i in c.pagto[1].ledger.lancamentos(pid) if i.tipo is TipoLancamento.REEMBOLSO
    ]


def abrir_disputa(c, pid) -> None:
    http = c.pagto[0]
    corpo = {
        "motivo": "nao_compareceu",
        "descricao": "Combinou e não veio.",
        "fotos": [{"arquivo_id": str(uuid.uuid4()), "tirada_em": datetime.now(UTC).isoformat()}],
    }
    r = http.post(f"/v1/pedidos/{pid}/disputa", json=corpo, headers=c.token("cliente"))
    assert r.status_code == 201, r.text
    r = http.post(f"/v1/pedidos/{pid}/disputa/resposta", headers=c.token("profissional"))
    assert r.status_code == 200, r.text


def test_disputa_estorna_o_retido_reenvio_nao_duplica_e_compensacao_fica_bloqueada(amb):
    c = amb
    servico = c.pagto[2]
    pid, cobranca, prof = pago_com_liberacao_parcial(c)
    abrir_disputa(c, pid)
    r = decidir(c, pid, "med_a", "reembolso_total")  # o congelado é só o que está retido
    assert r.status_code == 200, r.text
    assert devolvido(c, cobranca) == [RETIDO] and reembolsos(c, pid) == [RETIDO]
    assert saldos(c, pid, prof) == (0, 0, LIBERADO)  # o liberado não foi tocado

    decidir(c, pid, "med_a", "reembolso_total")
    servico.reenviar_estornos(pid)
    assert devolvido(c, cobranca) == [RETIDO] and reembolsos(c, pid) == [RETIDO]
    assert [o.valor_centavos for o in servico.ordens.do_pedido(pid)] == [RETIDO]

    antes = c.pagto[1].ledger.lancamentos(pid)
    r = c.pagto[0].post(
        "/v1/admin/compensacoes",
        json={"pedido_id": pid, "valor_centavos": LIBERADO, "motivo": "Compensar o liberado."},
        headers=c.token("med_a"),
    )
    assert r.status_code in (409, 422), r.text
    assert c.pagto[1].compensacoes.listar(pedido_id=pid)[1] == 0
    assert c.pagto[1].ledger.lancamentos(pid) == antes
    assert devolvido(c, cobranca) == [RETIDO]
    assert r.json()["codigo"] == "reembolso_direto_na_disputa", r.text


@pytest.mark.parametrize("tipo", ["estorno", "contestacao"])
def test_webhook_lanca_o_retido_sem_pedir_nada_ao_provedor(amb, tipo):
    c = amb
    servico = c.pagto[2]
    pid, cobranca, prof = pago_com_liberacao_parcial(c)
    parte = RETIDO // 2
    extra = {"evento_id": f"evt_{uuid.uuid4().hex}", "valor_centavos": parte}
    if tipo == "contestacao":
        evento = TipoEvento.CONTESTACAO
        extra |= {
            "status_contestacao": "lost",
            "tipo_stripe": "charge.dispute.closed",
            "objeto_id": f"dp_{uuid.uuid4().hex}",
        }
    else:
        evento = TipoEvento.ESTORNO_CONFIRMADO
    chamadas = len(servico.provedor.chamadas)
    for _ in range(2):  # o provedor reenvia o mesmo evento
        r = webhook(c, evento, cobranca, **extra)
        assert r.status_code == 200, r.text
    assert reembolsos(c, pid) == [parte]
    assert saldos(c, pid, prof) == (RETIDO - parte, 0, LIBERADO)
    assert servico.cobrancas.obter(cobranca).estornado_centavos == parte
    assert list(servico.ordens.do_pedido(pid)) == []  # o dinheiro já voltou: nenhuma ordem
    assert devolvido(c, cobranca) == []
    assert not any(x[0] == "estornar" for x in servico.provedor.chamadas[chamadas:])


def test_webhook_acima_do_retido_nao_lanca(amb):
    c = amb
    pid, cobranca, prof = pago_com_liberacao_parcial(c)
    antes = c.pagto[1].ledger.lancamentos(pid)
    r = webhook(
        c,
        TipoEvento.ESTORNO_CONFIRMADO,
        cobranca,
        evento_id=f"evt_{uuid.uuid4().hex}",
        valor_centavos=RETIDO + 1,
    )
    assert r.status_code == 200, r.text
    assert c.pagto[1].ledger.lancamentos(pid) == antes
    assert saldos(c, pid, prof) == (RETIDO, 0, LIBERADO)
    assert list(c.pagto[2].ordens.do_pedido(pid)) == []


# --- com a 20261128040000: o teto do banco passa a contar o reembolso direto ------------------


@pytest.fixture
def com_048(amb):
    """Aplica a migration só durante o teste (o resto do módulo roda sem ela)."""
    nome = "20261128040000_compensacao_conta_reembolso_retido"
    with amb.local.admin() as con:
        desfazer = _aplicar(
            con,
            f"{nome}.sql",
            f"{nome}_rollback.sql",
            "select strpos(prosrc, '/retido/custodia') > 0 from pg_proc "
            "where oid = 'public.compensacao_estornado_ao_cliente(uuid)'::regprocedure",
        )
    yield amb
    zerar(amb)
    with amb.local.admin() as con:
        for sql in desfazer:
            con.execute(sql)


def compensar(c, pid, valor):
    return c.pagto[0].post(
        "/v1/admin/compensacoes",
        json={"pedido_id": pid, "valor_centavos": valor, "motivo": "Compensar o liberado."},
        headers=c.token("med_a"),
    )


def test_deteccao_da_migration_falha_fechada(amb):
    assert amb.pagto[1].compensacoes.conta_reembolso_retido() is False


def test_com_a_migration_alem_do_decidido_e_recusado(com_048):
    c = com_048
    assert c.pagto[1].compensacoes.conta_reembolso_retido() is True
    pid, cobranca, _ = pago_com_liberacao_parcial(c)
    abrir_disputa(c, pid)
    decidido = RETIDO // 2
    r = decidir(c, pid, "med_a", "reembolso_parcial", valor_cliente_centavos=decidido)
    assert r.status_code == 200, r.text
    assert reembolsos(c, pid) == [decidido]  # o decidido já voltou inteiro, direto
    antes = c.pagto[1].ledger.lancamentos(pid)
    r = compensar(c, pid, 1)  # há valor liberado e pago pelo cliente: só o teto recusa
    assert r.status_code == 422, r.text
    assert (r.json()["codigo"], r.json()["maximo_centavos"]) == ("acima_do_devido", 0)
    assert c.pagto[1].ledger.lancamentos(pid) == antes
    assert devolvido(c, cobranca) == [decidido]


def test_com_a_migration_dentro_do_decidido_e_aceito_uma_vez(com_048):
    c = com_048
    contexto = c.pagto[1]
    pid, cobranca, _ = pago_e_agendado(c)
    abrir_disputa(c, pid)  # congela o valor inteiro
    prof = contexto.pedidos.obter(pid).profissional_id
    livro = Livro()
    livro.lancar_varios(list(contexto.ledger.lancamentos(pid)))
    antes = len(livro.lancamentos)
    agora = datetime.now(UTC)
    repartir_custodia(livro, pid, prof, 0, f"teste:{pid}:rep", agora, LIBERADO)
    liberar(livro, pid, prof, f"teste:{pid}:lib", agora)
    contexto.ledger.lancar_varios(list(livro.lancamentos[antes:]))
    r = decidir(c, pid, "med_a", "reembolso_total")  # decidido: o valor inteiro
    assert r.status_code == 200, r.text
    assert reembolsos(c, pid) == [RETIDO]
    r = compensar(c, pid, LIBERADO + 1)
    assert (r.status_code, r.json()["codigo"]) == (422, "acima_do_devido"), r.text
    assert r.json()["maximo_centavos"] == LIBERADO
    r = compensar(c, pid, LIBERADO)
    assert r.status_code == 200 and r.json()["resultado"] == "ok", r.text
    r = compensar(c, pid, LIBERADO)
    assert r.status_code == 200 and r.json()["resultado"] == "ja_registrada", r.text
    assert sorted(devolvido(c, cobranca)) == sorted([RETIDO, LIBERADO])
    assert RETIDO + LIBERADO == VALOR_ORCAMENTO
