import pytest

from trato.pagamentos.custo import (
    ConfigCustoPagamento,
    MeioPagamento,
    TaxaMeio,
    calcular_custo_stripe,
)

# Taxas de exemplo SÓ para teste (as reais vêm da configuração).
CONFIG = ConfigCustoPagamento(
    pix=TaxaMeio(percentual_bps=100),  # 1,00%
    cartao=TaxaMeio(percentual_bps=399, fixo_centavos=39),  # 3,99% + R$ 0,39
    adicional_parcelamento_bps={2: 200, 3: 250, 12: 600},
)


def test_pix_percentual_simples():
    assert calcular_custo_stripe(10_000, MeioPagamento.PIX, CONFIG) == 100


def test_cartao_a_vista_percentual_mais_fixo():
    # 10000 * 3,99% = 399 + 39 fixo
    assert calcular_custo_stripe(10_000, MeioPagamento.CARTAO, CONFIG) == 438


def test_cartao_parcelado_soma_adicional_ao_percentual():
    # 399 + 200 = 599 bps -> 599 + 39
    assert calcular_custo_stripe(10_000, MeioPagamento.CARTAO, CONFIG, parcelas=2) == 638
    # 399 + 600 = 999 bps -> 999 + 39
    assert calcular_custo_stripe(10_000, MeioPagamento.CARTAO, CONFIG, parcelas=12) == 1038


def test_arredondamento_meio_para_cima():
    # 150 * 1% = 1,5 -> 2 ; 149 * 1% = 1,49 -> 1 ; 50 * 1% = 0,5 -> 1 ; 49 -> 0
    assert calcular_custo_stripe(150, MeioPagamento.PIX, CONFIG) == 2
    assert calcular_custo_stripe(149, MeioPagamento.PIX, CONFIG) == 1
    assert calcular_custo_stripe(50, MeioPagamento.PIX, CONFIG) == 1
    assert calcular_custo_stripe(49, MeioPagamento.PIX, CONFIG) == 0


def test_arredondamento_acontece_uma_vez_so():
    # 125 * 599 bps = 7,4875 -> 7. Arredondar por parte daria 5 (4,99) + 3 (2,5) = 8.
    assert calcular_custo_stripe(125, MeioPagamento.CARTAO, CONFIG, parcelas=2) == 7 + 39


def test_resultado_e_sempre_int():
    custo = calcular_custo_stripe(12_345, MeioPagamento.CARTAO, CONFIG, parcelas=3)
    assert type(custo) is int


def test_parcelamento_nao_configurado_e_recusado():
    with pytest.raises(ValueError, match="não configurado"):
        calcular_custo_stripe(10_000, MeioPagamento.CARTAO, CONFIG, parcelas=5)


def test_pix_nao_parcela():
    with pytest.raises(ValueError, match="Pix"):
        calcular_custo_stripe(10_000, MeioPagamento.PIX, CONFIG, parcelas=2)


@pytest.mark.parametrize("valor", [0, -1])
def test_valor_deve_ser_positivo(valor):
    with pytest.raises(ValueError):
        calcular_custo_stripe(valor, MeioPagamento.PIX, CONFIG)


@pytest.mark.parametrize("valor", [100.5, "100", True])
def test_recusa_float_texto_e_bool(valor):
    with pytest.raises(TypeError):
        calcular_custo_stripe(valor, MeioPagamento.PIX, CONFIG)


def test_parcelas_menor_que_um_e_recusada():
    with pytest.raises(ValueError):
        calcular_custo_stripe(10_000, MeioPagamento.CARTAO, CONFIG, parcelas=0)


def test_config_recusa_taxa_negativa_e_parcelamento_invalido():
    with pytest.raises(ValueError):
        TaxaMeio(percentual_bps=-1)
    with pytest.raises(ValueError):
        ConfigCustoPagamento(
            pix=TaxaMeio(100), cartao=TaxaMeio(399), adicional_parcelamento_bps={1: 10}
        )


def test_config_nao_muda_depois_de_criada():
    origem = {2: 200}
    config = ConfigCustoPagamento(
        pix=TaxaMeio(100), cartao=TaxaMeio(399), adicional_parcelamento_bps=origem
    )
    origem[2] = 9_999
    assert config.adicional_parcelamento_bps[2] == 200
