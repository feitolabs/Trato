"""BE-PARCELAS: valor de cada parcela (Termos 6.4) e validade dos Tratinhos (13.3)."""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_moedas import ligar

from trato.api.moedas import LancamentoMoeda
from trato.api.rotas_app import OpcaoParcelamentoOut
from trato.pagamentos.parcelamento import (
    ConfigParcelamento,
    dividir_em_parcelas,
    juros_mensal_bps,
)
from trato.pedidos.estados import Estado

D = timedelta(days=1)


@pytest.mark.parametrize("parcelas", range(2, 13))
@pytest.mark.parametrize("total", [1, 100, 10_001, 99_999, 90_000])
def test_a_soma_das_parcelas_e_sempre_o_total(total, parcelas):
    valores = dividir_em_parcelas(total, parcelas)
    assert len(valores) == parcelas and sum(valores) == total
    assert set(valores[:-1]) == {total // parcelas} and valores[-1] >= valores[0]


def test_opcoes_informam_custo_sem_mudar_o_total_nem_o_campo_antigo():
    opcoes = ConfigParcelamento({2: 0, 3: 349}).opcoes(10_000)
    sem, com = opcoes
    assert (sem.sem_juros, sem.diferenca_a_vista_centavos, sem.custo_total_bps) == (True, 0, 0)
    assert (com.sem_juros, com.diferenca_a_vista_centavos, com.custo_total_bps) == (
        False,
        349,
        349,
    )
    assert com.total_centavos == 10_349 and com.valor_parcela_centavos == 3_449
    assert com.valores_parcelas_centavos == (3_449, 3_449, 3_451)
    assert com.ultima_parcela_centavos == 3_451
    assert sem.juros_mensal_bps == 0 and com.juros_mensal_bps > 0


@pytest.mark.parametrize("parcelas", [2, 3, 6, 12])
@pytest.mark.parametrize("base", [101, 10_000, 99_999, 5_000_000])
@pytest.mark.parametrize("custo_bps", [150, 349, 1_200, 10_000])
def test_juros_ao_mes_e_coerente_com_as_parcelas_cobradas(parcelas, base, custo_bps):
    (opcao,) = ConfigParcelamento({parcelas: custo_bps}).opcoes(base)

    def presente(bps: float) -> float:
        fator = 1 + bps / 10_000
        return sum(v / fator**k for k, v in enumerate(opcao.valores_parcelas_centavos, 1))

    bps = opcao.juros_mensal_bps
    assert bps >= 1 and not opcao.sem_juros
    # a taxa exata fica a no máximo meio bps do valor informado
    assert presente(bps + 0.5) < base <= presente(bps - 0.5) + 1e-6 or bps == 1


def test_juros_ao_mes_conhecido_usa_a_ultima_parcela():
    # Price: R$ 1.000,00 em 3x a 1,99% a.m. = 3 parcelas de R$ 346,68.
    assert juros_mensal_bps(100_000, (34_668, 34_668, 34_668)) == 199
    # a diferença na última parcela muda a taxa
    assert juros_mensal_bps(100_000, (34_668, 34_668, 35_668)) > 199
    assert juros_mensal_bps(100_000, (33_333, 33_333, 33_334)) == 0


def test_rotas_de_pagamento_publicam_a_taxa_ao_mes():
    (opcao,) = ConfigParcelamento({3: 349}).opcoes(10_000)
    saida = OpcaoParcelamentoOut(**vars(opcao)).model_dump()
    assert saida["juros_mensal_bps"] == opcao.juros_mensal_bps and saida["sem_juros"] is False
    assert saida["total_centavos"] == 10_349


def test_creditos_do_profissional_com_validade_separados_do_cliente(amb):
    def creditar(chave, usuario, carteira, quantidade, dias):
        amb.contexto.moedas.lancar(
            LancamentoMoeda(
                usuario,
                "bonus_avaliacao",
                quantidade,
                chave,
                AGORA - D,
                expira_em=AGORA + dias * D,
                carteira=carteira,
            )
        )

    creditar("depois", PROFISSIONAL.id, "profissional", 30, 60)
    creditar("antes", PROFISSIONAL.id, "profissional", 10, 5)
    creditar("vencido", PROFISSIONAL.id, "profissional", 99, -1)
    r = amb.cliente.get("/v1/me/moedas", headers=cab("t-prof")).json()
    assert [c["moedas"] for c in r["creditos_profissional"]] == [10, 30]
    assert all(c["expira_em"] for c in r["creditos_profissional"]) and r["creditos"] == []
    cliente = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).json()
    assert cliente["creditos_profissional"] == [] and CLIENTE.id != PROFISSIONAL.id


def test_indicacoes_informam_a_validade_configurada(amb):
    r = amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    assert r.json()["resumo"]["validade_dias"] == amb.contexto.indicacoes.config().validade_dias


def test_avaliacao_informa_a_validade_do_bonus_anunciado_e_do_ganho(amb):
    ligar(amb, bonus_avaliacao_moedas=50, validade_dias=120)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    url = "/v1/pedidos/ped-1/avaliacao"
    antes = amb.cliente.get(url, headers=cab("t-cliente")).json()
    assert (antes["bonus_moedas"], antes["bonus_validade_dias"]) == (50, 120)
    feita = amb.cliente.post(url, json={"nota_geral": 5}, headers=cab("t-cliente")).json()
    assert (feita["moedas_ganhas"], feita["bonus_validade_dias"]) == (50, 120)
    depois = amb.cliente.get(url, headers=cab("t-cliente")).json()
    assert (depois["bonus_moedas"], depois["bonus_validade_dias"]) == (0, None)
