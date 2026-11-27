"""BE-ORFAO: o estorno de pagamento órfão nunca sai da custódia paga por outra cobrança.
Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import timedelta

import pytest
from test_fluxo_pagamento_e2e import VALOR, fluxo  # noqa: F401
from test_orcamento_vencido import aceito, estornos, pagar_em

from trato.financeiro.ledger import CUSTODIA
from trato.pagamentos.modelos import EstadoCobranca
from trato.pagamentos.provedor.base import TipoEvento


def custodia(f, pid) -> int:
    return f.ctx.ledger.saldo_da_conta(CUSTODIA, pid)


def duas(f) -> tuple[str, dict, dict]:
    """Pedido com a primeira cobrança trocada por outra."""
    pid = aceito(f, timedelta(days=3))
    velha = f.cobrar(pid)
    r = f.chamar("POST", f"/v1/pedidos/{pid}/cobranca", "t-cliente", {"meio": "cartao"})
    assert r.status_code == 201, r.text
    assert r.json()["id"] != velha["id"]
    return pid, velha, r.json()


def orfa(f) -> tuple[str, dict, dict]:
    pid, velha, nova = duas(f)
    assert pagar_em(f, nova["id"]).status_code == 200
    assert pagar_em(f, velha["id"], evento_id="evt_velha").status_code == 200
    assert custodia(f, pid) == VALOR
    return pid, velha, nova


def aviso(f, cobranca, evento="evt_ref", **kw):
    return f.webhook(TipoEvento.ESTORNO_CONFIRMADO, cobranca["id"], evento_id=evento, **kw)


def local(f, cobranca):
    return f.servico.cobrancas.obter(cobranca["id"])


def revisoes(f) -> list[str]:
    return [m for _, m in f.ctx.eventos_webhook.em_revisao()]


def test_cobranca_trocada_e_cancelada_no_provedor(fluxo):
    _, velha, nova = duas(fluxo)
    assert ("cancelar_cobranca", velha["id"]) in fluxo.fake.chamadas
    assert ("cancelar_cobranca", nova["id"]) not in fluxo.fake.chamadas


def test_aviso_do_estorno_orfao_nao_mexe_na_custodia(fluxo):
    pid, velha, nova = orfa(fluxo)
    gravada = local(fluxo, velha)
    assert gravada.status is EstadoCobranca.DEVOLVIDA
    assert gravada.estornado_centavos == velha["valor_centavos"]
    antes = fluxo.tipos(pid)
    for evento in ("evt_ref", "evt_ref", "evt_ref_2"):
        assert aviso(fluxo, velha, evento).status_code == 200
    assert custodia(fluxo, pid) == VALOR and fluxo.tipos(pid) == antes
    assert revisoes(fluxo) == [] and local(fluxo, nova).estornado_centavos == 0
    assert estornos(fluxo, velha["id"]) == [velha["valor_centavos"]]


@pytest.mark.parametrize("trocada", [True, False])
def test_aviso_antes_de_gravar_a_devolucao(fluxo, trocada):
    """O provedor já devolveu, mas a transação do órfão não gravou (ou ainda não confirmou)."""
    pid, velha, nova = duas(fluxo)
    assert pagar_em(fluxo, nova["id"]).status_code == 200
    if not trocada:
        fluxo.servico.cobrancas.salvar(
            replace(local(fluxo, velha), status=EstadoCobranca.AGUARDANDO)
        )
    fluxo.fake.marcar_paga(velha["id"])
    fluxo.fake.estornar(velha["id"], None, f"orfao/{velha['id']}")
    assert aviso(fluxo, velha).status_code == 200
    assert custodia(fluxo, pid) == VALOR and revisoes(fluxo) == []
    assert local(fluxo, velha).status is EstadoCobranca.DEVOLVIDA
    assert pagar_em(fluxo, velha["id"], evento_id="evt_velha").status_code == 200
    assert custodia(fluxo, pid) == VALOR
    assert estornos(fluxo, velha["id"]) == [velha["valor_centavos"]]


def test_registro_antigo_sem_o_valor_devolvido_nao_mexe_na_custodia(fluxo):
    pid, velha, _ = orfa(fluxo)
    fluxo.servico.cobrancas.salvar(replace(local(fluxo, velha), estornado_centavos=0))
    assert aviso(fluxo, velha).status_code == 200
    disputa = fluxo.webhook(
        TipoEvento.CONTESTACAO, velha["id"], evento_id="evt_cb", status_contestacao="lost"
    )
    assert disputa.status_code == 200
    assert custodia(fluxo, pid) == VALOR


def test_contestacao_perdida_da_orfa_nao_mexe_na_custodia(fluxo):
    pid, velha, _ = orfa(fluxo)
    r = fluxo.webhook(
        TipoEvento.CONTESTACAO, velha["id"], evento_id="evt_cb", status_contestacao="lost"
    )
    assert r.status_code == 200 and custodia(fluxo, pid) == VALOR
    assert any("não restava nada" in m for m in revisoes(fluxo))


def test_parcial_antes_do_pagamento_espera_e_depois_concilia(fluxo):
    pid = aceito(fluxo, timedelta(days=3))
    cobranca = fluxo.cobrar(pid)
    r = aviso(fluxo, cobranca, valor_centavos=1_000)
    assert r.status_code == 409, r.text
    assert local(fluxo, cobranca).status is EstadoCobranca.AGUARDANDO
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200
    assert aviso(fluxo, cobranca, valor_centavos=1_000).status_code == 200
    assert custodia(fluxo, pid) == VALOR - 1_000


def test_reembolso_inteiro_por_fora_antes_do_pagamento_nao_contrata(fluxo):
    pid = aceito(fluxo, timedelta(days=3))
    cobranca = fluxo.cobrar(pid)
    assert aviso(fluxo, cobranca).status_code == 200
    assert any("nada lançado" in m for m in revisoes(fluxo))
    assert pagar_em(fluxo, cobranca["id"]).status_code == 200
    assert custodia(fluxo, pid) == 0 and fluxo.tipos(pid) == []


@pytest.mark.parametrize("parte", [1_000, VALOR])
def test_reembolso_por_fora_da_cobranca_paga_continua_conciliado(fluxo, parte):
    pid, _, nova = orfa(fluxo)
    for evento in ("evt_fora", "evt_fora", "evt_fora_2"):
        assert aviso(fluxo, nova, evento, valor_centavos=parte).status_code == 200
    assert custodia(fluxo, pid) == VALOR - parte
    assert local(fluxo, nova).estornado_centavos == parte
    assert sum("conciliado no ledger" in m for m in revisoes(fluxo)) == 1


def test_orfao_e_aviso_ao_mesmo_tempo(fluxo):
    pid, velha, nova = duas(fluxo)
    assert pagar_em(fluxo, nova["id"]).status_code == 200
    fluxo.fake.marcar_paga(velha["id"])

    def avisar_depois_do_provedor(evento):
        # O parceiro só avisa depois de estornar; a gravação local pode ainda não ter acontecido.
        for _ in range(1_000):
            if estornos(fluxo, velha["id"]):
                return aviso(fluxo, velha, evento)
            time.sleep(0.005)
        raise AssertionError("o provedor não estornou")

    chamadas = [
        lambda: avisar_depois_do_provedor("evt_a1"),
        lambda: pagar_em(fluxo, velha["id"], evento_id="evt_v1"),
        lambda: avisar_depois_do_provedor("evt_a2"),
        lambda: pagar_em(fluxo, velha["id"], evento_id="evt_v2"),
    ]
    with ThreadPoolExecutor(4) as grupo:
        respostas = list(grupo.map(lambda f: f(), chamadas))
    assert {r.status_code for r in respostas} == {200}
    assert custodia(fluxo, pid) == VALOR and revisoes(fluxo) == []
    assert estornos(fluxo, velha["id"]) == [velha["valor_centavos"]]
    assert local(fluxo, velha).status is EstadoCobranca.DEVOLVIDA
