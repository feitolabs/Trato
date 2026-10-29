import pytest

from trato.pagamentos.taxa import ConfigTaxa, TabelaProgressivaNaoImplementada, calcular_taxa

CFG = ConfigTaxa(taxa_bps=750, taxa_minima_centavos=500)


def test_percentual_com_arredondamento_meio_para_cima():
    assert calcular_taxa(100_000, CFG) == 7_500
    assert calcular_taxa(10_001, CFG) == 750  # 750,075 -> 750
    assert calcular_taxa(10_007, CFG) == 751  # 750,525 -> 751


def test_minimo_vale_para_servico_pequeno_mas_nunca_passa_do_valor():
    assert calcular_taxa(2_000, CFG) == 500
    assert calcular_taxa(300, CFG) == 300


def test_recusa_float_valor_zero_e_config_invalida():
    with pytest.raises(TypeError):
        calcular_taxa(100.0, CFG)  # type: ignore[arg-type]
    with pytest.raises(ValueError):
        calcular_taxa(0, CFG)
    with pytest.raises(ValueError):
        ConfigTaxa(-1, 0)
    with pytest.raises(ValueError):
        ConfigTaxa(10_001, 0)


def test_tabela_progressiva_fica_desligada():
    with pytest.raises(TabelaProgressivaNaoImplementada):
        calcular_taxa(10_000, ConfigTaxa(750, 500, tabela_progressiva_ligada=True))
