"""Fechamento mensal (totais, hash, trava) e extrato do profissional em PDF. Só memória."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.financeiro import extrato_profissional, fechamento, periodo
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.financeiro.ledger import (
    Livro,
    estornar_pedido,
    liberar,
    registrar_cobranca,
    repartir_custodia,
    separar_custo_parcelamento,
)
from trato.financeiro.pdf import PdfSimples

OUTUBRO = datetime(2026, 10, 15, 15, 0, tzinfo=UTC)


def _pedido_concluido(
    livro: Livro, pedido: str, quando: datetime, valor=10_750, taxa=750, profissional="pro-1"
):
    registrar_cobranca(livro, pedido, valor, f"cob/pi_{pedido}", quando)
    repartir_custodia(livro, pedido, profissional, taxa, f"din/{pedido}/rep", quando)


def test_totais_do_mes_fecham_entre_si():
    livro = Livro()
    _pedido_concluido(livro, "p1", OUTUBRO)
    liberar(livro, "p1", "pro-1", "liq/p1", OUTUBRO + timedelta(days=2))
    registrar_cobranca(livro, "p2", 5_750, "cob/pi_p2", OUTUBRO)
    separar_custo_parcelamento(livro, "p2", 750, "cob/pi_p2", OUTUBRO)
    estornar_pedido(livro, "p2", 2_000, "din/p2/disputa/est", OUTUBRO + timedelta(days=1))
    # Um pedido de novembro não entra em outubro.
    _pedido_concluido(livro, "p3", datetime(2026, 11, 2, 12, 0, tzinfo=UTC))

    t = fechamento.calcular(livro.lancamentos, (), 2026, 10)

    assert t.mes == "2026-10" and t.cobrancas == 2
    assert t.cobrado_centavos == 10_750 + 5_750
    assert t.devolvido_centavos == 2_000
    assert t.entrada_liquida_centavos == t.cobrado_centavos - t.devolvido_centavos
    assert t.receita_taxas_centavos == 1_500  # taxa de p1 + custo de parcelamento de p2
    assert t.liberado_profissionais_centavos == 10_000
    assert t.retido_fim_centavos == 5_000 - 2_000  # p2 segue retido, menos o que voltou
    assert t.a_liberar_fim_centavos == 0 and t.liberado_fim_centavos == 10_000


def test_mes_vai_ate_a_meia_noite_de_brasilia():
    livro = Livro()
    # 01/11 às 01:00 UTC ainda é 31/10 às 22:00 em Brasília.
    _pedido_concluido(livro, "p1", datetime(2026, 11, 1, 1, 0, tzinfo=UTC))
    assert fechamento.calcular(livro.lancamentos, (), 2026, 10).cobrancas == 1
    assert fechamento.calcular(livro.lancamentos, (), 2026, 11).cobrancas == 0


def test_contestacao_perdida_conta_no_mes_em_que_encerrou():
    perdida = Contestacao(
        "dp_1", 4_000, StatusContestacao.PERDIDA, OUTUBRO, OUTUBRO, encerrada_em=OUTUBRO
    )
    aberta = Contestacao("dp_2", 9_000, StatusContestacao.ABERTA, OUTUBRO, OUTUBRO)
    t = fechamento.calcular((), (perdida, aberta), 2026, 10)
    assert t.contestacoes_perdidas == 1 and t.contestacoes_perdidas_centavos == 4_000


def test_hash_muda_com_qualquer_centavo_e_mes_so_fecha_uma_vez():
    livro = Livro()
    _pedido_concluido(livro, "p1", OUTUBRO)
    t = fechamento.calcular(livro.lancamentos, (), 2026, 10)
    f = fechamento.montar(t, "eq-fin", datetime(2026, 11, 3, tzinfo=UTC), "Fechamento de outubro")
    outro = dict(f.totais, cobrado_centavos=f.totais["cobrado_centavos"] + 1)
    assert fechamento.hash_dos_totais(outro) != f.hash

    repo = fechamento.FechamentosEmMemoria()
    repo.gravar(f)
    with pytest.raises(fechamento.MesJaFechado):
        repo.gravar(f)


def test_so_fecha_mes_que_ja_terminou_em_brasilia():
    fim_de_outubro = periodo.mes(2026, 10)[1]
    assert not fechamento.pode_fechar(2026, 10, fim_de_outubro - timedelta(seconds=1))
    assert fechamento.pode_fechar(2026, 10, fim_de_outubro)


def test_extrato_do_profissional_soma_recebido_e_estorno():
    livro = Livro()
    _pedido_concluido(livro, "p1", OUTUBRO)
    liberar(livro, "p1", "pro-1", "liq/p1", OUTUBRO + timedelta(days=1))
    # ainda a liberar; sem taxa, para o estorno sair todo do "a liberar"
    _pedido_concluido(livro, "p2", OUTUBRO + timedelta(days=3), valor=10_000, taxa=0)
    estornar_pedido(livro, "p2", 3_000, "din/p2/disputa/est", OUTUBRO + timedelta(days=4))
    _pedido_concluido(livro, "p3", OUTUBRO, profissional="pro-2")
    liberar(livro, "p3", "pro-2", "liq/p3", OUTUBRO)  # de outro profissional: não entra

    desde, ate = periodo.mes(2026, 10)
    e = extrato_profissional.montar(livro.lancamentos, "pro-1", desde, ate)

    assert e.recebido_centavos == 10_000
    # O reembolso de 30 saiu do "a liberar" (líquido 70), não do que ele já recebeu.
    assert e.estornado_centavos == 0
    assert e.a_liberar_fim_centavos == 7_000
    assert [lin.descricao for lin in e.linhas] == ["Recebido"]


def test_extrato_vira_pdf_valido_com_acentos():
    livro = Livro()
    _pedido_concluido(livro, "p1", OUTUBRO)
    liberar(livro, "p1", "pro-1", "liq/p1", OUTUBRO + timedelta(days=1))
    desde, ate = periodo.mes(2026, 10)
    e = extrato_profissional.montar(livro.lancamentos, "pro-1", desde, ate)

    conteudo = extrato_profissional.pdf(
        e, "João Pintor", {"p1": (10482, "Pintura da sala")}, OUTUBRO
    )

    assert conteudo.startswith(b"%PDF-1.4") and conteudo.rstrip().endswith(b"%%EOF")
    assert "João Pintor".encode("cp1252") in conteudo
    assert b"PED-10482" in conteudo and b"R$ 10.000,00"[:3] in conteudo
    assert b"Per\xedodo: 01/10/2026 a 31/10/2026" in conteudo


def test_pdf_com_muitas_linhas_abre_novas_paginas():
    doc = PdfSimples()
    for _ in range(3):
        doc.texto(50, 50, "linha (com parênteses) e \\ barra")
        doc.nova_pagina()
    conteudo = doc.bytes()
    assert b"/Count 4" in conteudo
    assert b"\\(com par\xeanteses\\)" in conteudo


def test_reais_no_formato_brasileiro():
    assert extrato_profissional.reais(1_234_567) == "R$ 12.345,67"
    assert extrato_profissional.reais(-50) == "-R$ 0,50"
