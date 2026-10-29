import pytest

from trato.margem.regras import Faixa, ModoProgressivo, TaxaProgressiva, TaxaUnica

FAIXAS = (Faixa(50_000, 750), Faixa(150_000, 500), Faixa(None, 350))


def test_taxa_unica_percentual():
    assert TaxaUnica(750).calcular(10_000) == 750


def test_taxa_unica_minimo_vira_piso():
    assert TaxaUnica(500, minimo_centavos=500).calcular(8_000) == 500  # 4,00 -> 5,00


def test_taxa_unica_nunca_passa_do_ticket():
    assert TaxaUnica(500, minimo_centavos=500).calcular(300) == 300


def test_taxa_unica_arredonda_meio_para_cima():
    # 7,5% de 101 = 7,575 -> 8 ; 7,5% de 100 = 7,5 -> 8 ; 7,5% de 66 = 4,95 -> 5
    assert TaxaUnica(750).calcular(101) == 8
    assert TaxaUnica(750).calcular(100) == 8
    assert TaxaUnica(750).calcular(66) == 5
    # 5% de 10 = 0,5 -> 1 ; 5% de 9 = 0,45 -> 0
    assert TaxaUnica(500).calcular(10) == 1
    assert TaxaUnica(500).calcular(9) == 0


def test_progressiva_marginal_soma_as_fatias():
    regra = TaxaProgressiva(FAIXAS)
    # 500 a 7,5% = 37,50 ; (1000 - 500) a 5% = 25,00
    assert regra.calcular(100_000) == 3_750 + 2_500
    # 500 a 7,5% + 1000 a 5% + 1500 a 3,5% = 37,50 + 50,00 + 52,50
    assert regra.calcular(300_000) == 3_750 + 5_000 + 5_250


def test_progressiva_limite_da_faixa_e_inclusivo():
    regra = TaxaProgressiva(FAIXAS)
    assert regra.calcular(50_000) == 3_750
    assert regra.calcular(50_001) == 3_750  # 1 centavo a 5% = 0,05 -> arredonda a 3_750


def test_progressiva_marginal_continua_sem_degrau():
    regra = TaxaProgressiva(FAIXAS)
    assert regra.calcular(50_100) - regra.calcular(50_000) == 5  # 100 cent a 5%


def test_progressiva_arredonda_uma_vez_so():
    # 3 faixas de 1 centavo cada: 1 x 7,5% + 1 x 5% + 1 x 3,5% = 0,16 -> 0.
    # Arredondar por faixa daria 0 + 0 + 0; já 2 centavos em faixas de 50% dão 1 certo.
    regra = TaxaProgressiva((Faixa(1, 5_000), Faixa(2, 5_000), Faixa(None, 0)))
    assert regra.calcular(2) == 1  # 0,5 + 0,5 = 1,0 (por faixa daria 1 + 1 = 2)


def test_progressiva_faixa_inteira_tem_degrau():
    regra = TaxaProgressiva(FAIXAS, modo=ModoProgressivo.FAIXA_INTEIRA)
    assert regra.calcular(50_000) == 3_750  # 7,5%
    assert regra.calcular(50_001) == 2_500  # 5% sobre o ticket inteiro (2500,05 -> 2500)
    assert regra.calcular(300_000) == 10_500  # 3,5%


def test_progressiva_minimo():
    regra = TaxaProgressiva(FAIXAS, minimo_centavos=500)
    assert regra.calcular(4_000) == 500


def test_resultados_sao_int():
    assert type(TaxaUnica(750).calcular(12_345)) is int
    assert type(TaxaProgressiva(FAIXAS).calcular(123_457)) is int


@pytest.mark.parametrize(
    "faixas",
    [
        (),
        (Faixa(100, 500),),  # falta a faixa sem limite
        (Faixa(None, 500), Faixa(None, 400)),  # sem limite fora da última
        (Faixa(200, 500), Faixa(100, 400), Faixa(None, 300)),  # limites não crescentes
        (Faixa(100, 10_001), Faixa(None, 300)),  # percentual > 100%
    ],
)
def test_progressiva_recusa_tabela_invalida(faixas):
    with pytest.raises(ValueError):
        TaxaProgressiva(faixas)


def test_recusa_float_e_valores_invalidos():
    with pytest.raises(TypeError):
        TaxaUnica(7.5)
    with pytest.raises(TypeError):
        TaxaUnica(750, minimo_centavos=5.0)
    with pytest.raises(ValueError):
        TaxaUnica(-1)
    with pytest.raises(ValueError):
        TaxaUnica(750, minimo_centavos=-1)
    with pytest.raises(TypeError):
        TaxaProgressiva((Faixa(None, 750.0),))
