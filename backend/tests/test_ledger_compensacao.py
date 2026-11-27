"""TERMOS-BE-86: o livro aceita os lançamentos de compensação (8.6 e 17.4)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.financeiro import extrato_profissional
from trato.financeiro.ledger import (
    CLIENTE,
    CUSTODIA,
    TAXA_TRATO,
    EstornoInvalido,
    Lancamento,
    LancamentoInvalido,
    Livro,
    SaldoInsuficiente,
    TipoLancamento,
    a_compensar,
    estornar_pedido,
    liberado,
    liberar,
    registrar_cobranca,
    repartir_custodia,
    separar_custo_parcelamento,
)

AGORA = datetime(2026, 11, 26, 12, 0, tzinfo=UTC)
PRO = "pro-1"


def _lanc(chave, tipo, debito, credito, valor, estorno=None):
    return Lancamento(chave, "ped-1", tipo, debito, credito, valor, AGORA, estorno_de=estorno)


def _livro_liberado(valor=10_000) -> Livro:
    livro = Livro()
    registrar_cobranca(livro, "ped-1", valor, "cob", AGORA)
    repartir_custodia(livro, "ped-1", PRO, 0, "rep", AGORA)
    liberar(livro, "ped-1", PRO, "lib", AGORA)
    return livro


def test_divida_compensacao_e_cancelamento_carregam_e_fecham():
    livro = _livro_liberado()
    divida = _lanc("d", TipoLancamento.REEMBOLSO, a_compensar(PRO), CLIENTE, 4_000)
    desconto = _lanc("c", TipoLancamento.REPASSE, liberado(PRO), a_compensar(PRO), 4_000)
    livro.lancar_varios([divida, desconto])
    assert livro.saldo(liberado(PRO)) == 6_000 and livro.saldo(a_compensar(PRO)) == 0
    estorno = _lanc(
        "e", TipoLancamento.ESTORNO, a_compensar(PRO), liberado(PRO), 4_000, desconto.id
    )
    assume = _lanc("a", TipoLancamento.REEMBOLSO, TAXA_TRATO, a_compensar(PRO), 4_000)
    livro.lancar_varios([estorno, assume])
    assert livro.saldo(liberado(PRO)) == 10_000 and livro.saldo(TAXA_TRATO) == -4_000
    assert livro.saldo(a_compensar(PRO)) == 0
    livro.verificar_partidas()
    novo = Livro()  # releitura do banco: a ordem dos lançamentos basta
    novo.lancar_varios(livro.lancamentos)
    extrato = extrato_profissional.montar(
        novo.lancamentos, PRO, AGORA - timedelta(days=1), AGORA + timedelta(days=1)
    )
    assert [lin.descricao for lin in extrato.linhas] == [
        "Recebido",
        "Compensação",
        "Compensação devolvida",
    ]


def test_so_os_pares_novos_dispensam_saldo():
    livro = _livro_liberado(1_000)
    with pytest.raises(SaldoInsuficiente):  # o liberado continua exigindo saldo
        livro.lancar(_lanc("x", TipoLancamento.REPASSE, liberado(PRO), a_compensar(PRO), 1_001))
    with pytest.raises(LancamentoInvalido):
        _lanc("y", TipoLancamento.REEMBOLSO, CUSTODIA, CLIENTE, 1)
    with pytest.raises(LancamentoInvalido):
        _lanc("z", TipoLancamento.REPASSE, a_compensar(PRO), liberado(PRO), 1)


@pytest.mark.parametrize("valor", [1, 9_999, 10_000, 10_001, 10_006, 10_499, 10_500])
def test_estorno_com_custo_do_parcelado_em_toda_a_faixa(valor):
    """Serviço 10.000 e parcelado 500: entre o serviço e o total o excedente é custo (M2)."""
    livro = Livro()
    registrar_cobranca(livro, "ped-1", 10_500, "cob", AGORA)
    separar_custo_parcelamento(livro, "ped-1", 500, "cob", AGORA)
    estornar_pedido(livro, "ped-1", valor, "est", AGORA, incluir_custo=True)
    assert -livro.saldo(CLIENTE) == 10_500 - valor
    assert livro.saldo(CUSTODIA) == 10_500 - valor and livro.saldo(TAXA_TRATO) == 0
    livro.verificar_partidas()
    estornar_pedido(livro, "ped-1", valor, "est", AGORA, incluir_custo=True)  # reenvio
    assert -livro.saldo(CLIENTE) == 10_500 - valor


@pytest.mark.parametrize("valor", [10_001, 10_500])
def test_sem_incluir_o_custo_o_teto_continua_o_servico(valor):
    livro = Livro()
    registrar_cobranca(livro, "ped-1", 10_500, "cob", AGORA)
    separar_custo_parcelamento(livro, "ped-1", 500, "cob", AGORA)
    with pytest.raises(EstornoInvalido):
        estornar_pedido(livro, "ped-1", valor, "est", AGORA)
