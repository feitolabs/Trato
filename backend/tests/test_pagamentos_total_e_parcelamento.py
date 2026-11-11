"""Taxa DESCONTADA do profissional (João, 10/11/2026) e custo de parcelamento repassado."""

from __future__ import annotations

import pytest

from trato.pagamentos.parcelamento import (
    ConfigParcelamento,
    ParcelamentoIndisponivel,
)
from trato.pagamentos.taxa import ConfigTaxa, montar_total

CONFIG = ConfigTaxa(750, 300)  # 7,5% e mínima R$ 3,00 (config; aqui só nos testes)


def test_taxa_e_descontada_do_profissional_e_o_cliente_paga_o_orcamento():
    t = montar_total(10_000, CONFIG)
    assert t.taxa_centavos == 750
    assert t.cobrado_centavos == 10_000  # o cliente paga só o orçamento
    assert t.liquido_profissional_centavos == 9_250
    assert t.receita_trato_centavos == 750
    assert t.custo_parcelamento_centavos == 0


def test_taxa_minima_tambem_sai_do_profissional():
    t = montar_total(3_000, CONFIG)  # 7,5% de R$ 30,00 = R$ 2,25 < mínimo R$ 3,00
    assert (t.taxa_centavos, t.cobrado_centavos) == (300, 3_000)
    assert t.liquido_profissional_centavos == 2_700


def test_custo_de_parcelamento_e_repassado_por_cima_e_nao_vira_receita():
    t = montar_total(10_000, CONFIG, custo_parcelamento_centavos=215)
    assert t.cobrado_centavos == 10_000 + 215
    assert t.receita_trato_centavos == 750
    assert t.liquido_profissional_centavos == 9_250


def test_total_recusa_float_e_custo_negativo():
    with pytest.raises(TypeError):
        montar_total(10_000, CONFIG, custo_parcelamento_centavos=1.5)  # type: ignore[arg-type]
    with pytest.raises(ValueError):
        montar_total(10_000, CONFIG, custo_parcelamento_centavos=-1)


def test_parcelamento_vazio_esta_desligado_e_nao_inventa_valor():
    vazio = ConfigParcelamento()
    assert not vazio.ligado and vazio.opcoes(10_750) == []
    assert vazio.custo_centavos(10_750, 1) == 0
    with pytest.raises(ParcelamentoIndisponivel):
        vazio.custo_centavos(10_750, 3)


def test_parcelamento_calcula_o_total_por_parcelas_da_tabela():
    cfg = ConfigParcelamento({3: 200, 6: 400})  # valores de TESTE, não do provedor
    assert cfg.ligado
    (tres, seis) = cfg.opcoes(10_750)
    assert (tres.parcelas, tres.custo_centavos, tres.total_centavos) == (3, 215, 10_965)
    assert tres.valor_parcela_centavos == 3_655
    assert (seis.custo_centavos, seis.total_centavos) == (430, 11_180)
    with pytest.raises(ParcelamentoIndisponivel):
        cfg.custo_centavos(10_750, 4)


def test_tabela_de_parcelamento_invalida_e_recusada():
    for ruim in ({1: 100}, {13: 100}, {3: -1}, {3: 10_001}, {3: 1.5}):
        with pytest.raises(ValueError):
            ConfigParcelamento(ruim)  # type: ignore[arg-type]
