"""O Trato é 100% gratuito: nenhuma taxa, em nenhum valor (decisão de 18/11/2026)."""

import pytest

from trato.pagamentos import taxa
from trato.pagamentos.taxa import ConfigTaxa, calcular_taxa, montar_total

pytestmark = pytest.mark.app_gratuito
CONFIG_ANTIGA = ConfigTaxa(taxa_bps=750, taxa_minima_centavos=300)


def test_padrao_de_producao_e_gratuito():
    assert taxa.APP_GRATUITO is True


@pytest.mark.parametrize("valor", [1, 100, 2_000, 10_000, 5_000_000])
def test_taxa_e_zero_mesmo_com_taxa_congelada_no_contrato(valor):
    assert calcular_taxa(valor, CONFIG_ANTIGA) == 0


def test_profissional_recebe_o_valor_inteiro():
    t = montar_total(10_000, CONFIG_ANTIGA)
    assert (t.taxa_centavos, t.liquido_profissional_centavos, t.receita_trato_centavos) == (
        0,
        10_000,
        0,
    )
    assert t.cobrado_centavos == 10_000


def test_valor_invalido_continua_recusado():
    with pytest.raises(ValueError):
        calcular_taxa(0, CONFIG_ANTIGA)
