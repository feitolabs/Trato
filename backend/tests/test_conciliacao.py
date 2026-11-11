"""Conciliação do ledger espelho com o extrato do provedor (V2.5). Sem rede: Stripe simulado."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

import pytest

from trato.financeiro import periodo
from trato.financeiro.conciliacao import (
    CONFERE,
    SO_NO_PROVEDOR,
    SO_NO_TRATO,
    VALOR_DIFERENTE,
    conciliar,
    referencia_da_cobranca,
)
from trato.financeiro.ledger import (
    Livro,
    estornar_pedido,
    registrar_cobranca,
    separar_custo_parcelamento,
)
from trato.pagamentos.provedor import ErroProvedor, MovimentoProvedor, TipoMovimento
from trato.pagamentos.provedor.stripe_teste import ProvedorStripeTeste

DIA = date(2026, 11, 6)
DESDE, ATE = periodo.dia(DIA)
MEIO_DIA = DESDE + timedelta(hours=12)


def mov(tipo, valor, ref, quando=MEIO_DIA, taxa=0, mid=None):
    return MovimentoProvedor(mid or f"txn_{ref}_{tipo}_{valor}", tipo, valor, taxa, quando, ref)


def livro_com_cobranca(pedido="ped-1", ref="pi_1", valor=10_750, quando=MEIO_DIA) -> Livro:
    livro = Livro()
    registrar_cobranca(livro, pedido, valor, f"cob/{ref}", quando)
    separar_custo_parcelamento(livro, pedido, 750, f"cob/{ref}", quando)
    return livro


def test_referencia_sai_das_duas_chaves_de_cobranca_e_ignora_o_relancamento():
    assert referencia_da_cobranca("cob/pi_123") == "pi_123"
    assert referencia_da_cobranca("cobranca:ped-1:pi_9") == "pi_9"
    assert referencia_da_cobranca("din/ped-1/disputa/est/mantida/cobranca") is None
    assert referencia_da_cobranca("cob-ped-1") is None


def test_dia_conferido_com_taxa_do_provedor_somada():
    livro = livro_com_cobranca()
    r = conciliar(
        [mov(TipoMovimento.COBRANCA, 10_750, "pi_1", taxa=430)],
        livro.lancamentos,
        DESDE,
        ATE,
    )
    assert r.confere
    assert [(lin.tipo, lin.situacao) for lin in r.linhas] == [("cobranca", CONFERE)]
    assert r.cobrado_provedor_centavos == r.cobrado_trato_centavos == 10_750
    assert r.taxas_provedor_centavos == 430


def test_cobranca_so_no_provedor_so_no_trato_e_valor_diferente():
    livro = livro_com_cobranca("ped-1", "pi_1", 10_750)
    registrar_cobranca(livro, "ped-2", 5_000, "cob/pi_2", MEIO_DIA)
    registrar_cobranca(livro, "ped-3", 8_000, "cob/pi_3", MEIO_DIA)
    movimentos = [
        mov(TipoMovimento.COBRANCA, 10_700, "pi_1"),  # o provedor diz 50 centavos a menos
        mov(TipoMovimento.COBRANCA, 5_000, "pi_2"),
        mov(TipoMovimento.COBRANCA, 3_000, "pi_9"),  # o Trato nunca soube desse pagamento
    ]

    r = conciliar(movimentos, livro.lancamentos, DESDE, ATE)

    por_ref = {lin.referencia: lin for lin in r.linhas}
    assert por_ref["pi_1"].situacao == VALOR_DIFERENTE and por_ref["pi_1"].diferenca_centavos == -50
    assert por_ref["pi_2"].situacao == CONFERE and por_ref["pi_2"].pedido_id == "ped-2"
    assert por_ref["pi_3"].situacao == SO_NO_TRATO
    assert por_ref["pi_9"].situacao == SO_NO_PROVEDOR
    assert len(r.divergencias) == 3 and not r.confere


def test_aviso_que_chega_depois_da_meia_noite_ainda_casa():
    livro = livro_com_cobranca(quando=ATE + timedelta(minutes=3))
    r = conciliar(
        [mov(TipoMovimento.COBRANCA, 10_750, "pi_1", quando=ATE - timedelta(seconds=5))],
        livro.lancamentos,
        DESDE,
        ATE,
    )
    assert r.confere


def test_estorno_parcial_conta_so_o_que_voltou_ao_cliente():
    livro = livro_com_cobranca()
    estornar_pedido(livro, "ped-1", 4_000, "din/ped-1/disputa/est", MEIO_DIA)

    r = conciliar(
        [
            mov(TipoMovimento.COBRANCA, 10_750, "pi_1"),
            mov(TipoMovimento.ESTORNO, -4_000, "pi_1"),
        ],
        livro.lancamentos,
        DESDE,
        ATE,
    )

    (estorno,) = [lin for lin in r.linhas if lin.tipo == "estorno"]
    assert estorno.referencia == "ped-1" and estorno.valor_trato_centavos == 4_000
    assert r.confere


def test_contestacao_aberta_aparece_como_diferenca_ate_ser_perdida():
    livro = livro_com_cobranca()
    movimentos = [
        mov(TipoMovimento.COBRANCA, 10_750, "pi_1"),
        mov(TipoMovimento.CONTESTACAO, -10_000, "pi_1"),
    ]
    aberta = conciliar(movimentos, livro.lancamentos, DESDE, ATE)
    assert [lin.situacao for lin in aberta.divergencias] == [SO_NO_PROVEDOR]

    estornar_pedido(livro, "ped-1", 10_000, "contest/dp_1", MEIO_DIA)
    perdida = conciliar(movimentos, livro.lancamentos, DESDE, ATE)
    assert perdida.confere


def test_repasse_e_saque_nao_entram_na_comparacao():
    r = conciliar(
        [mov(TipoMovimento.REPASSE, -9_000, None), mov(TipoMovimento.SAQUE, -9_000, None)],
        (),
        DESDE,
        ATE,
    )
    assert r.confere and r.movimentos_ignorados == 2


# --- Stripe: extrato paginado lido sem rede -----------------------------------------------------


def _stripe(paginas):
    chamadas = []

    def transporte(metodo, caminho, campos, cabecalhos):
        chamadas.append((metodo, caminho, dict(campos)))
        return 200, paginas[len(chamadas) - 1]

    return ProvedorStripeTeste("sk_test_x", "whsec_x", transporte), chamadas


def _linha(i, tipo, valor, fonte):
    return {"id": f"txn_{i}", "type": tipo, "amount": valor, "fee": 40, "created": 1_793_000_000,
            "source": fonte}  # fmt: skip


def test_stripe_le_todas_as_paginas_do_extrato_e_acha_a_cobranca():
    provedor, chamadas = _stripe(
        [
            {"has_more": True, "data": [_linha(1, "charge", 10_750, {"payment_intent": "pi_1"})]},
            {
                "has_more": False,
                "data": [
                    _linha(2, "refund", -4_000, {"charge": {"payment_intent": "pi_1"}}),
                    _linha(3, "payout", -6_000, {"id": "po_1"}),
                ],
            },
        ]
    )

    movimentos = provedor.movimentos(DESDE, ATE)

    assert [(m.tipo, m.cobranca_id) for m in movimentos] == [
        (TipoMovimento.COBRANCA, "pi_1"),
        (TipoMovimento.ESTORNO, "pi_1"),
        (TipoMovimento.SAQUE, None),
    ]
    assert chamadas[0][1] == "/v1/balance_transactions"
    assert chamadas[0][2]["created[gte]"] == str(int(DESDE.timestamp()))
    assert chamadas[1][2]["starting_after"] == "txn_1"
    assert movimentos[0].criado_em.tzinfo is UTC


def test_stripe_recusando_vira_erro_do_provedor():
    def transporte(metodo, caminho, campos, cabecalhos):
        return 401, {"error": {"message": "chave inválida"}}

    provedor = ProvedorStripeTeste("sk_test_x", "whsec_x", transporte)
    with pytest.raises(ErroProvedor):
        provedor.movimentos(DESDE, ATE)


def test_dia_e_mes_no_horario_de_brasilia():
    desde, ate = periodo.dia(DIA)
    assert desde == datetime(2026, 11, 6, 3, 0, tzinfo=UTC)
    assert ate - desde == timedelta(days=1)
    inicio, fim = periodo.mes(2026, 12)
    assert inicio == datetime(2026, 12, 1, 3, 0, tzinfo=UTC)
    assert fim == datetime(2027, 1, 1, 3, 0, tzinfo=UTC)
    assert periodo.mes_de(datetime(2026, 11, 1, 2, 0, tzinfo=UTC)) == (2026, 10)
    assert periodo.ler_mes("2026-10") == (2026, 10)
    with pytest.raises(ValueError):
        periodo.ler_mes("2026-13")
