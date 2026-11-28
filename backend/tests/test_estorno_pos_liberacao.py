"""BE-SALDO-ESTORNO: depois de uma liberação parcial, o saldo ainda retido pode voltar."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest

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
    a_liberar,
    custo_parcelamento_em_aberto,
    estornar_pedido,
    liberado,
    liberar,
    reembolso_total_com_custo,
    registrar_cobranca,
    registrar_repasse,
    repartir_custodia,
    separar_custo_parcelamento,
)

AGORA = datetime(2026, 11, 28, 12, 0, tzinfo=UTC)
PRO = "pro-1"


def parcial(custo=0, valor_liberado=4_000, repartir=10_000) -> Livro:
    """Serviço 10.000 (+ custo do parcelado): reparte `repartir` e libera `valor_liberado`."""
    livro = Livro()
    registrar_cobranca(livro, "p", 10_000 + custo, "cob", AGORA)
    if custo:
        separar_custo_parcelamento(livro, "p", custo, "cob", AGORA)
    repartir_custodia(livro, "p", PRO, 0, "rep", AGORA, repartir)
    liberar(livro, "p", PRO, "lib", AGORA, valor_liberado)
    return livro


def foto(livro):
    return (
        -livro.saldo(CLIENTE),
        livro.saldo(CUSTODIA),
        livro.saldo(a_liberar(PRO)),
        livro.saldo(liberado(PRO)),
        livro.saldo(TAXA_TRATO),
    )


@pytest.mark.parametrize("repartir", [10_000, 7_000])  # tudo a liberar | parte ainda na custódia
def test_estorna_o_restante_depois_da_liberacao_parcial_e_o_reenvio_nao_repete(repartir):
    livro = parcial(repartir=repartir)
    estornar_pedido(livro, "p", 6_000, "est", AGORA)
    assert foto(livro) == (4_000, 0, 0, 4_000, 0)  # o liberado não é tocado
    antes = livro.lancamentos
    estornar_pedido(livro, "p", 6_000, "est", AGORA)
    assert livro.lancamentos == antes
    livro.verificar_partidas()


def test_parcial_do_restante_deixa_o_resto_retido():
    livro = parcial(repartir=7_000)
    estornar_pedido(livro, "p", 3_500, "est", AGORA)
    assert foto(livro) == (6_500, 0, 2_500, 4_000, 0)
    liberar(livro, "p", PRO, "lib2", AGORA)
    assert foto(livro) == (6_500, 0, 0, 6_500, 0)


@pytest.mark.parametrize("valor", [6_001, 10_000, 0, -1])
def test_acima_do_saldo_recusa_sem_gravar(valor):
    livro = parcial()
    antes = livro.lancamentos
    with pytest.raises((EstornoInvalido, SaldoInsuficiente)):
        estornar_pedido(livro, "p", valor, "est", AGORA)
    assert livro.lancamentos == antes


def test_o_liberado_ja_pago_ao_profissional_continua_intocado():
    livro = parcial()
    registrar_repasse(livro, "p", PRO, 4_000, "pago", AGORA)
    with pytest.raises(SaldoInsuficiente):
        estornar_pedido(livro, "p", 6_001, "est", AGORA)
    estornar_pedido(livro, "p", 6_000, "est", AGORA)
    assert foto(livro) == (4_000, 0, 0, 0, 0)


def test_tudo_liberado_e_pago_nao_vira_reembolso_total_com_custo():
    livro = parcial(custo=500, valor_liberado=10_000)
    registrar_repasse(livro, "p", PRO, 10_000, "pago", AGORA)
    assert reembolso_total_com_custo(livro.lancamentos, "p", PRO) is None


@pytest.mark.parametrize(
    ("valor", "kw", "custo_que_fica"),
    [
        (6_500, {"incluir_custo": True}, 0),
        (6_200, {"incluir_custo": True}, 300),
        (3_000, {"incluir_custo": True}, 500),
        (6_000, {"custo_devolvido": 300}, 200),
        (6_000, {}, 500),
    ],
)
def test_custo_do_parcelado_so_volta_quando_pedido(valor, kw, custo_que_fica):
    livro = parcial(custo=500)
    estornar_pedido(livro, "p", valor, "est", AGORA, **kw)
    assert -livro.saldo(CLIENTE) == 10_500 - valor - kw.get("custo_devolvido", 0)
    assert custo_parcelamento_em_aberto(livro, "p") == custo_que_fica
    assert livro.saldo(TAXA_TRATO) == custo_que_fica
    livro.verificar_partidas()


@pytest.mark.parametrize(
    ("kw", "valor"), [({"incluir_custo": True}, 6_501), ({"custo_devolvido": 501}, 6_000)]
)
def test_custo_acima_do_cobrado_recusa(kw, valor):
    livro = parcial(custo=500)
    antes = livro.lancamentos
    with pytest.raises((EstornoInvalido, SaldoInsuficiente)):
        estornar_pedido(livro, "p", valor, "est", AGORA, **kw)
    assert livro.lancamentos == antes


@pytest.mark.parametrize(
    ("chave", "conta"),
    [
        ("est", CUSTODIA),
        ("est/retido/a-liberar", CUSTODIA),
        ("est/retido/custodia", TAXA_TRATO),
        ("est/custo-devolvido", CUSTODIA),
    ],
)
def test_reembolso_direto_so_com_a_chave_da_propria_conta(chave, conta):
    with pytest.raises(LancamentoInvalido):
        Lancamento(chave, "p", TipoLancamento.REEMBOLSO, conta, CLIENTE, 1, AGORA)
