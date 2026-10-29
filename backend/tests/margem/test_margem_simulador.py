import pytest

from trato.margem.regras import Faixa, TaxaProgressiva, TaxaUnica
from trato.margem.relatorio import gerar_tabelas
from trato.margem.simulador import Metodo, PremissasCusto, simular_margem
from trato.pagamentos.custo import ConfigCustoPagamento, TaxaMeio

# Taxas de exemplo SÓ para teste (as reais vêm da configuração).
PROVEDOR = ConfigCustoPagamento(
    pix=TaxaMeio(percentual_bps=100),  # 1,00%
    cartao=TaxaMeio(percentual_bps=400, fixo_centavos=40),  # 4,00% + R$ 0,40
    adicional_parcelamento_bps={3: 150, 6: 300},
)
UNICA = TaxaUnica(750, minimo_centavos=500)
PROGRESSIVA = TaxaProgressiva((Faixa(50_000, 750), Faixa(150_000, 500), Faixa(None, 350)))


def test_pix_sem_outros_custos():
    r = simular_margem(10_000, Metodo.pix(), UNICA, PROVEDOR)
    assert r.bruto_centavos == 10_000
    assert r.taxa_trato_centavos == 750
    assert r.custo_provedor_centavos == 100
    assert r.liquido_profissional_centavos == 9_250
    assert r.margem_centavos == 650
    assert r.margem_bps_da_taxa == 8_667  # 650/750 = 86,67%
    assert r.margem_bps_do_bruto == 650  # 6,50%
    assert r.margem_negativa is False


def test_cartao_a_vista():
    r = simular_margem(10_000, Metodo.cartao(), UNICA, PROVEDOR)
    assert r.custo_provedor_centavos == 440  # 400 + 40
    assert r.margem_centavos == 310


def test_cartao_parcelado_3x_e_6x():
    r3 = simular_margem(10_000, Metodo.cartao(3), UNICA, PROVEDOR)
    r6 = simular_margem(10_000, Metodo.cartao(6), UNICA, PROVEDOR)
    assert r3.custo_provedor_centavos == 590  # 550 bps -> 550 + 40
    assert r6.custo_provedor_centavos == 740  # 700 bps -> 700 + 40
    assert r3.margem_centavos == 160
    assert r6.margem_centavos == 10


def test_parcelado_pode_deixar_margem_negativa():
    r = simular_margem(10_000, Metodo.cartao(6), TaxaUnica(500), PROVEDOR)
    assert r.margem_centavos == 500 - 740
    assert r.margem_negativa is True
    assert r.margem_bps_da_taxa == -4_800


def test_todos_os_custos_da_v2_entram_na_margem():
    premissas = PremissasCusto(
        chargeback_bps_pix=0,
        chargeback_bps_cartao=100,  # 1% do ticket
        suporte_centavos=200,
        garantia_centavos=150,
        tributos_bps=1_000,  # 10% da taxa do Trato
        incentivo_centavos=50,
    )
    r = simular_margem(10_000, Metodo.cartao(), UNICA, PROVEDOR, premissas)
    assert r.chargeback_esperado_centavos == 100
    assert r.tributos_centavos == 75
    # 750 - 440 - 100 - 200 - 150 - 75 - 50
    assert r.margem_centavos == -265
    assert r.margem_negativa is True


def test_chargeback_depende_do_metodo():
    premissas = PremissasCusto(chargeback_bps_pix=10, chargeback_bps_cartao=100)
    pix = simular_margem(10_000, Metodo.pix(), UNICA, PROVEDOR, premissas)
    cartao = simular_margem(10_000, Metodo.cartao(), UNICA, PROVEDOR, premissas)
    assert pix.chargeback_esperado_centavos == 10
    assert cartao.chargeback_esperado_centavos == 100


def test_regra_progressiva():
    r = simular_margem(100_000, Metodo.pix(), PROGRESSIVA, PROVEDOR)
    assert r.taxa_trato_centavos == 6_250
    assert r.custo_provedor_centavos == 1_000
    assert r.margem_centavos == 5_250
    assert r.liquido_profissional_centavos == 93_750


def test_arredondamento_do_tributo_e_do_chargeback_half_up():
    # taxa de 5 centavos (mín.) com 10% = 0,5 -> 1 ; ticket 150 com 1% = 1,5 -> 2
    premissas = PremissasCusto(chargeback_bps_cartao=100, tributos_bps=1_000)
    r = simular_margem(150, Metodo.cartao(), TaxaUnica(0, minimo_centavos=5), PROVEDOR, premissas)
    assert r.taxa_trato_centavos == 5
    assert r.tributos_centavos == 1
    assert r.chargeback_esperado_centavos == 2


def test_margem_percentual_com_taxa_zero_nao_divide_por_zero():
    r = simular_margem(10_000, Metodo.pix(), TaxaUnica(0), PROVEDOR)
    assert r.taxa_trato_centavos == 0
    assert r.margem_bps_da_taxa is None
    assert r.margem_negativa is True  # sobra só o custo do provedor


@pytest.mark.parametrize("ticket", [8_000, 12_345, 99_999, 300_001])
@pytest.mark.parametrize("metodo", [Metodo.pix(), Metodo.cartao(), Metodo.cartao(3)])
@pytest.mark.parametrize("regra", [UNICA, PROGRESSIVA])
def test_soma_exata_em_centavos_e_sempre_int(ticket, metodo, regra):
    premissas = PremissasCusto(
        chargeback_bps_cartao=37, suporte_centavos=123, garantia_centavos=45, tributos_bps=333
    )
    r = simular_margem(ticket, metodo, regra, PROVEDOR, premissas)
    assert r.liquido_profissional_centavos + r.taxa_trato_centavos == r.bruto_centavos
    assert r.margem_centavos == (
        r.taxa_trato_centavos
        - r.custo_provedor_centavos
        - r.chargeback_esperado_centavos
        - r.suporte_centavos
        - r.garantia_centavos
        - r.tributos_centavos
        - r.incentivo_centavos
    )
    assert r.margem_negativa == (r.margem_centavos < 0)
    for valor in (r.taxa_trato_centavos, r.custo_provedor_centavos, r.margem_centavos):
        assert type(valor) is int


def test_recusa_ticket_invalido():
    with pytest.raises(ValueError):
        simular_margem(0, Metodo.pix(), UNICA, PROVEDOR)
    with pytest.raises(TypeError):
        simular_margem(100.0, Metodo.pix(), UNICA, PROVEDOR)


def test_parcelamento_nao_configurado_e_pix_parcelado_sao_recusados():
    with pytest.raises(ValueError, match="não configurado"):
        simular_margem(10_000, Metodo.cartao(4), UNICA, PROVEDOR)
    with pytest.raises(ValueError, match="Pix"):
        simular_margem(10_000, Metodo(Metodo.pix().meio, 2), UNICA, PROVEDOR)


def test_premissas_recusam_negativo_e_float():
    with pytest.raises(ValueError):
        PremissasCusto(suporte_centavos=-1)
    with pytest.raises(TypeError):
        PremissasCusto(tributos_bps=10.5)


def test_rotulos_dos_metodos():
    assert Metodo.pix().rotulo == "Pix"
    assert Metodo.cartao().rotulo == "Cartão à vista"
    assert Metodo.cartao(6).rotulo == "Cartão 6x"


def test_relatorio_gera_as_tres_regras_e_marca_negativos():
    texto = gerar_tabelas()
    assert "5% fixa" in texto and "7,5% fixa" in texto and "Progressiva" in texto
    assert "⚠️" in texto
    assert "Onde a margem fica negativa" in texto
