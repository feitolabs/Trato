import dataclasses
from datetime import UTC, datetime

import pytest

from trato.financeiro.ledger import (
    CLIENTE,
    CUSTODIA,
    ChaveReutilizada,
    Conta,
    EstornoInvalido,
    Lancamento,
    LancamentoInvalido,
    Livro,
    SaldoInsuficiente,
    TipoConta,
    TipoLancamento,
    a_liberar,
    estornar,
    estornar_pedido,
    liberado,
    liberar,
    registrar_cobranca,
    registrar_gorjeta,
    registrar_repasse,
    repartir_custodia,
    repartir_proporcional,
)

T0 = datetime(2026, 11, 2, 9, 0, tzinfo=UTC)
PED = "ped1"
PROF = "p1"


def cobrado(valor=10_000, pedido=PED, chave="cob1"):
    livro = Livro()
    registrar_cobranca(livro, pedido, valor, chave, T0)
    return livro


def concluido(valor=10_000, taxa=750):
    livro = cobrado(valor)
    repartir_custodia(livro, PED, PROF, taxa, "fim1", T0)
    return livro


# --- Lançamento: valor, contas, imutabilidade -----------------------------------------


@pytest.mark.parametrize("valor", [0, -1, 10.5, "100", True])
def test_valor_invalido(valor):
    with pytest.raises(LancamentoInvalido):
        Lancamento("k", PED, TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, valor, T0)


def test_contas_incompativeis_com_o_tipo():
    with pytest.raises(LancamentoInvalido, match="incompatíveis"):
        Lancamento("k", PED, TipoLancamento.COBRANCA, CUSTODIA, CLIENTE, 100, T0)


def test_data_sem_fuso_e_estorno_sem_original():
    with pytest.raises(LancamentoInvalido, match="fuso"):
        Lancamento("k", PED, TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, 100, datetime(2026, 1, 1))  # noqa: DTZ001
    with pytest.raises(LancamentoInvalido, match="original"):
        Lancamento("k", PED, TipoLancamento.ESTORNO, CUSTODIA, CLIENTE, 100, T0)


def test_conta_do_profissional_exige_titular():
    with pytest.raises(LancamentoInvalido):
        Conta(TipoConta.A_LIBERAR)
    with pytest.raises(LancamentoInvalido):
        Conta(TipoConta.CUSTODIA, "p1")


def test_lancamento_e_imutavel():
    livro = cobrado()
    with pytest.raises(dataclasses.FrozenInstanceError):
        livro.lancamentos[0].valor = 1  # type: ignore[misc]


def test_livro_so_aceita_inclusao():
    livro = cobrado()
    for nome in ("editar", "apagar", "remover", "atualizar", "delete", "update", "clear"):
        assert not hasattr(livro, nome)
    assert isinstance(livro.lancamentos, tuple)
    # mexer na cópia não muda o livro
    livro.lancamentos[0:0]
    assert len(livro.lancamentos) == 1


# --- Idempotência ---------------------------------------------------------------------


def test_reenvio_nao_duplica():
    livro = cobrado()
    primeiro = livro.lancamentos[0]
    de_novo = registrar_cobranca(livro, PED, 10_000, "cob1", datetime(2026, 11, 3, tzinfo=UTC))
    assert de_novo is primeiro
    assert len(livro.lancamentos) == 1
    assert livro.saldo(CUSTODIA, PED) == 10_000


def test_mesma_chave_com_dados_diferentes_e_erro():
    livro = cobrado()
    with pytest.raises(ChaveReutilizada):
        registrar_cobranca(livro, PED, 9_999, "cob1", T0)
    with pytest.raises(ChaveReutilizada):
        registrar_cobranca(livro, "outro", 10_000, "cob1", T0)
    assert len(livro.lancamentos) == 1


def test_reenvio_de_operacao_com_varios_lancamentos():
    livro = concluido()
    n = len(livro.lancamentos)
    repartir_custodia(livro, PED, PROF, 750, "fim1", T0, valor=10_000)
    assert len(livro.lancamentos) == n


def test_lote_que_falha_nao_grava_nada():
    livro = cobrado()
    bom = Lancamento("a", PED, TipoLancamento.RETENCAO, CUSTODIA, a_liberar(PROF), 5_000, T0)
    ruim = Lancamento("b", PED, TipoLancamento.RETENCAO, CUSTODIA, a_liberar(PROF), 9_000, T0)
    with pytest.raises(SaldoInsuficiente):
        livro.lancar_varios([bom, ruim])
    assert len(livro.lancamentos) == 1
    assert livro.saldo(CUSTODIA, PED) == 10_000


# --- Fluxo e saldos -------------------------------------------------------------------


def test_cobranca_fica_retida():
    s = cobrado().saldos_pedido(PED, PROF)
    assert (s.cliente_pagou, s.retido, s.a_liberar, s.liberado, s.taxa_trato) == (
        10_000, 0 + 10_000, 0, 0, 0,
    )  # fmt: skip


def test_conclusao_reparte_taxa_e_profissional():
    s = concluido().saldos_pedido(PED, PROF)
    assert (s.retido, s.a_liberar, s.liberado, s.taxa_trato) == (0, 9_250, 0, 750)
    assert s.cliente_pagou == 10_000


def test_liberacao_e_repasse():
    livro = concluido()
    liberar(livro, PED, PROF, "lib1", T0)
    s = livro.saldos_pedido(PED, PROF)
    assert (s.a_liberar, s.liberado) == (0, 9_250)
    registrar_repasse(livro, PED, PROF, 9_000, "saque1", T0)
    assert livro.saldos_pedido(PED, PROF).liberado == 250


def test_repasse_acima_do_liberado_e_recusado():
    livro = concluido()
    liberar(livro, PED, PROF, "lib1", T0)
    with pytest.raises(SaldoInsuficiente):
        registrar_repasse(livro, PED, PROF, 9_251, "saque1", T0)


def test_nao_libera_o_que_ainda_esta_retido():
    livro = cobrado()
    with pytest.raises(LancamentoInvalido):
        liberar(livro, PED, PROF, "lib1", T0)  # nada a liberar (valor 0)
    with pytest.raises(SaldoInsuficiente):
        livro.lancar(Lancamento("x", PED, TipoLancamento.LIBERACAO, a_liberar(PROF),
                                liberado(PROF), 1, T0))  # fmt: skip


def test_taxa_maior_que_a_custodia_e_recusada():
    livro = cobrado()
    with pytest.raises(LancamentoInvalido):
        repartir_custodia(livro, PED, PROF, 10_001, "fim", T0)
    with pytest.raises(LancamentoInvalido):
        repartir_custodia(livro, PED, PROF, -1, "fim", T0)
    with pytest.raises(LancamentoInvalido):
        repartir_custodia(livro, PED, PROF, 7.5, "fim", T0)  # type: ignore[arg-type]


def test_taxa_zero_nao_gera_lancamento_de_taxa():
    livro = cobrado()
    novos = repartir_custodia(livro, PED, PROF, 0, "fim", T0)
    assert [n.tipo for n in novos] == [TipoLancamento.RETENCAO]


def test_gorjeta_vai_inteira_ao_profissional():
    livro = Livro()
    registrar_gorjeta(livro, PED, PROF, 500, "g1", T0)
    s = livro.saldos_pedido(PED, PROF)
    assert (s.liberado, s.taxa_trato, s.cliente_pagou) == (500, 0, 500)


def test_duas_cobrancas_30_e_70_por_cento():
    livro = Livro()
    registrar_cobranca(livro, PED, 3_000, "sinal", T0)
    registrar_cobranca(livro, PED, 7_000, "resto", T0)
    assert livro.saldos_pedido(PED).retido == 10_000


def test_saldos_separados_por_pedido():
    livro = cobrado(10_000, "A", "ca")
    registrar_cobranca(livro, "B", 4_000, "cb", T0)
    repartir_custodia(livro, "A", PROF, 500, "fa", T0)
    assert livro.saldos_pedido("A", PROF).retido == 0
    assert livro.saldos_pedido("B", PROF).retido == 4_000
    assert livro.saldo(CUSTODIA) == 4_000


# --- Partidas dobradas ----------------------------------------------------------------


def test_partidas_fecham_em_todo_passo_do_fluxo():
    livro = Livro()
    livro.verificar_partidas()
    registrar_cobranca(livro, PED, 12_345, "c", T0)
    livro.verificar_partidas()
    repartir_custodia(livro, PED, PROF, 926, "f", T0)
    livro.verificar_partidas()
    liberar(livro, PED, PROF, "l", T0)
    registrar_repasse(livro, PED, PROF, 1_000, "s", T0)
    registrar_gorjeta(livro, PED, PROF, 300, "g", T0)
    livro.verificar_partidas()
    assert livro.total_debitos() == livro.total_creditos() > 0


# --- Estorno --------------------------------------------------------------------------


def test_estorno_total_de_um_lancamento():
    livro = cobrado()
    original = livro.lancamentos[0]
    e = estornar(livro, original.id, None, "est1", T0)
    assert e.tipo is TipoLancamento.ESTORNO and e.estorno_de == original.id
    assert livro.saldos_pedido(PED).retido == 0
    assert livro.saldos_pedido(PED).cliente_pagou == 0
    livro.verificar_partidas()


def test_estorno_parcial_nao_passa_do_original():
    livro = cobrado()
    original = livro.lancamentos[0]
    estornar(livro, original.id, 4_000, "e1", T0)
    estornar(livro, original.id, 6_000, "e2", T0)
    with pytest.raises(EstornoInvalido, match="resta estornar"):
        estornar(livro, original.id, 1, "e3", T0)


def test_nao_estorna_estorno_nem_original_inexistente():
    livro = cobrado()
    e = estornar(livro, livro.lancamentos[0].id, 100, "e1", T0)
    with pytest.raises(EstornoInvalido, match="estorno"):
        estornar(livro, e.id, 100, "e2", T0)
    with pytest.raises(EstornoInvalido, match="não existe"):
        estornar(livro, "nada", 100, "e3", T0)


def test_estorno_com_contas_erradas_e_recusado():
    livro = cobrado()
    original = livro.lancamentos[0]
    torto = Lancamento("t", PED, TipoLancamento.ESTORNO, CLIENTE, CUSTODIA, 100, T0,
                       estorno_de=original.id)  # fmt: skip
    with pytest.raises(EstornoInvalido, match="inverter"):
        livro.lancar(torto)


def test_estorno_de_outro_pedido_e_recusado():
    livro = cobrado()
    registrar_cobranca(livro, "B", 5_000, "cb", T0)
    torto = Lancamento("t", "B", TipoLancamento.ESTORNO, CUSTODIA, CLIENTE, 100, T0,
                       estorno_de=livro.lancamentos[0].id)  # fmt: skip
    with pytest.raises(EstornoInvalido, match="mesmo pedido"):
        livro.lancar(torto)


def test_estorno_total_do_pedido_devolve_taxa_inteira():
    livro = concluido(10_000, 750)
    estornar_pedido(livro, PED, 10_000, "est", T0)
    s = livro.saldos_pedido(PED, PROF)
    assert (s.cliente_pagou, s.retido, s.a_liberar, s.taxa_trato) == (0, 0, 0, 0)
    livro.verificar_partidas()


def test_estorno_parcial_devolve_taxa_proporcional():
    livro = concluido(10_000, 750)
    estornar_pedido(livro, PED, 4_000, "est", T0)
    s = livro.saldos_pedido(PED, PROF)
    assert s.taxa_trato == 450  # 750 - 4000*750/10000 = 750 - 300
    assert s.a_liberar == 5_550  # 9250 - 3700
    assert s.cliente_pagou == 6_000
    assert s.taxa_trato + s.a_liberar == s.cliente_pagou
    livro.verificar_partidas()


def test_estorno_parcial_antes_de_concluir_sai_da_custodia():
    livro = cobrado()
    estornar_pedido(livro, PED, 3_000, "est", T0)
    s = livro.saldos_pedido(PED)
    assert (s.retido, s.cliente_pagou) == (7_000, 7_000)


def test_estorno_do_pedido_e_idempotente_e_atomico():
    livro = concluido()
    estornar_pedido(livro, PED, 4_000, "est", T0)
    n = len(livro.lancamentos)
    estornar_pedido(livro, PED, 4_000, "est", T0)  # reenvio (a tentativa já gravada)
    assert len(livro.lancamentos) == n


def test_estorno_do_pedido_acima_do_cobrado_e_recusado():
    livro = concluido()
    for valor in (0, 10_001, -5):
        with pytest.raises(EstornoInvalido):
            estornar_pedido(livro, PED, valor, "est", T0)
    assert len(livro.lancamentos) == 3


def test_estorno_do_que_ja_foi_sacado_e_recusado_sem_gravar_nada():
    livro = concluido()
    liberar(livro, PED, PROF, "lib", T0)
    registrar_repasse(livro, PED, PROF, 9_250, "saque", T0)
    n = len(livro.lancamentos)
    with pytest.raises(SaldoInsuficiente):
        estornar_pedido(livro, PED, 5_000, "est", T0)
    assert len(livro.lancamentos) == n


def test_estornos_parciais_sucessivos_ate_zerar():
    livro = concluido(10_001, 751)
    for i, valor in enumerate([3_333, 3_333, 3_335]):
        estornar_pedido(livro, PED, valor, f"est{i}", T0)
        livro.verificar_partidas()
    s = livro.saldos_pedido(PED, PROF)
    assert (s.cliente_pagou, s.a_liberar, s.taxa_trato, s.retido) == (0, 0, 0, 0)


# --- Sem perder centavo (varredura de valores) ----------------------------------------


def test_repartir_proporcional_exato():
    assert repartir_proporcional(10, [7, 7, 7]) == [4, 3, 3]
    assert repartir_proporcional(0, [5, 5]) == [0, 0]
    assert repartir_proporcional(7, [0, 7]) == [0, 7]
    with pytest.raises(ValueError):
        repartir_proporcional(11, [5, 5])


def test_repartir_proporcional_nunca_perde_centavo():
    for soma in (1, 3, 7, 100, 999, 10_001):
        for pesos in (
            [soma],
            [1, soma - 1] if soma > 1 else [soma],
            [soma // 3, soma // 3, soma - 2 * (soma // 3)],
        ):
            for total in range(0, soma + 1, max(1, soma // 37)):
                partes = repartir_proporcional(total, pesos)
                assert sum(partes) == total
                assert all(0 <= p <= w for p, w in zip(partes, pesos, strict=True))


def test_varredura_estorno_parcial_nao_cria_nem_perde_centavo():
    for valor, taxa in [(1, 0), (3, 1), (999, 75), (10_001, 751), (123_457, 9_259)]:
        passo = max(1, valor // 11)
        for devolver in range(1, valor + 1, passo):
            livro = concluido(valor, taxa)
            estornar_pedido(livro, PED, devolver, "est", T0)
            s = livro.saldos_pedido(PED, PROF)
            assert s.cliente_pagou == valor - devolver
            assert s.taxa_trato + s.a_liberar + s.retido == valor - devolver
            assert 0 <= s.taxa_trato <= taxa
            livro.verificar_partidas()
