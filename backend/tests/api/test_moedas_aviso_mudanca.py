"""BE-MOEDAS-30 (Termos 13.11 e I.12): melhora vale na hora; piora só com aviso de 30 dias; o uso
do que já foi creditado não piora enquanto valer. Memória; nada é enviado de verdade."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from conftest import CLIENTE, PROFISSIONAL
from test_avisos_previos import dia, enviar, preparar
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.admin.mudanca_moedas import PIORA_USO
from trato.api.moedas import ConfigMoedas, LancamentoMoeda, MoedasEmMemoria

URL = "/v1/admin/moedas/config"
CFG = {"ativo": True, "valor_moeda_centavos": 2, "max_reservas_abertas": 2}
PIOR_USO = {
    campo: getattr(ConfigMoedas(**CFG), campo) + direcao
    for campo, (direcao, _) in PIORA_USO.items()
}


@pytest.fixture
def amb2(fluxo):
    amb = fluxo.amb
    preparar(amb)
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(**CFG))
    return amb


def alterar(amb, referencia=None, **mudancas):
    atual = amb.cliente.get(URL, headers={"Authorization": "Bearer t-admin"}).json()
    corpo = atual | mudancas | {"motivo": "Ajuste do programa.", "aviso_referencia": referencia}
    return amb.cliente.put(URL, json=corpo, headers={"Authorization": "Bearer t-admin"})


def avisar(amb, mudancas, referencia="m1", dias=30):
    corpo = {
        "tipo": "tratinhos",
        "referencia": referencia,
        "vigencia": dia(amb, dias),
        "resumo": "Mudam regras do programa.",
    }
    if mudancas is not None:
        corpo["mudancas"] = mudancas
    r = enviar(amb, corpo)
    assert r.status_code == 200, r.text
    return r.json()


def creditar(amb, quantidade=100, usuario=CLIENTE.id, chave="c1", dias=90, **extra):
    agora = amb.contexto.agora()
    amb.contexto.moedas.lancar(
        LancamentoMoeda(
            usuario,
            "bonus_avaliacao",
            quantidade,
            chave,
            agora,
            expira_em=agora + timedelta(days=dias),
            **extra,
        )
    )


def recusado(r, codigo) -> bool:
    return r.status_code == 409 and r.json()["codigo"] == codigo


def test_piora_de_regra_exige_aviso_e_30_dias_completos(amb2):
    r = alterar(amb2, ativo=False)
    assert recusado(r, "aviso_obrigatorio") and r.json()["campos"] == ["ativo"], r.text
    avisar(amb2, {"ativo": False})
    assert recusado(alterar(amb2, ativo=False), "aviso_obrigatorio")  # sem `aviso_referencia`
    amb2.relogio.avancar(days=30, seconds=-1)
    r = alterar(amb2, "m1", ativo=False)
    assert recusado(r, "aviso_no_prazo") and r.json()["pode_valer_em"], r.text
    assert amb2.contexto.moedas.config().ativo is True
    amb2.relogio.avancar(seconds=1)
    assert alterar(amb2, "m1", ativo=False).status_code == 200
    assert amb2.contexto.moedas.config().ativo is False


def test_o_aviso_precisa_cobrir_o_campo_e_o_valor(amb2):
    avisar(amb2, None, "sem-valores")
    avisar(amb2, {"bonus_avaliacao_moedas": 40}, "m1")
    amb2.relogio.avancar(days=31)
    for ref in ("sem-valores", "outra"):
        assert recusado(alterar(amb2, ref, bonus_avaliacao_moedas=40), "aviso_obrigatorio")
    assert recusado(alterar(amb2, "m1", bonus_avaliacao_moedas=39), "aviso_obrigatorio")
    assert recusado(alterar(amb2, "m1", teto_mensal_moedas=1), "aviso_obrigatorio")
    assert alterar(amb2, "m1", bonus_avaliacao_moedas=45).status_code == 200  # melhor que o dito


def test_cada_aviso_vale_uma_vez(amb2):
    avisar(amb2, {"ativo": False})
    amb2.relogio.avancar(days=30)
    assert alterar(amb2, "m1", ativo=False).status_code == 200
    assert alterar(amb2, ativo=True).status_code == 200  # melhora: na hora
    assert recusado(alterar(amb2, "m1", ativo=False), "aviso_obrigatorio")


def test_envio_com_falha_nao_conta_ate_repetir_sem_falha(amb2, monkeypatch):
    notificador = amb2.contexto.extras["notificador"]
    original = notificador.notificar

    def falhar(evento, pessoa, **kw):
        if pessoa == CLIENTE.id:
            raise RuntimeError("fora do ar")
        return original(evento, pessoa, **kw)

    monkeypatch.setattr(notificador, "notificar", falhar)
    assert avisar(amb2, {"ativo": False})["falhas"] == 1
    amb2.relogio.avancar(days=30)
    assert recusado(alterar(amb2, "m1", ativo=False), "aviso_obrigatorio")


def test_melhora_vale_na_hora_mesmo_com_saldo(amb2):
    creditar(amb2)
    atual = ConfigMoedas(**CFG)
    melhor = {c: getattr(atual, c) - direcao for c, (direcao, _) in PIORA_USO.items()}
    r = alterar(amb2, **melhor, bonus_avaliacao_moedas=60)
    assert r.status_code == 200, r.text


@pytest.mark.parametrize("campo", sorted(PIORA_USO))
def test_uso_nao_piora_com_saldo_valido_nem_com_aviso(amb2, campo):
    creditar(amb2, dias=90)
    avisar(amb2, {campo: PIOR_USO[campo]})
    amb2.relogio.avancar(days=31)
    r = alterar(amb2, "m1", **{campo: PIOR_USO[campo]})
    assert recusado(r, "creditos_vigentes") and r.json()["campos"] == [campo], r.text
    amb2.relogio.avancar(days=60)  # venceu
    r = alterar(amb2, "m1", **{campo: PIOR_USO[campo]})
    assert r.status_code == 200, r.text


def test_saldo_gasto_nao_segura_e_carteira_do_profissional_segura(amb2):
    creditar(amb2)
    agora = amb2.contexto.agora()
    amb2.contexto.moedas.lancar(LancamentoMoeda(CLIENTE.id, "uso", -100, "gasto", agora))
    avisar(amb2, {"valor_moeda_centavos": 1})
    amb2.relogio.avancar(days=30)
    creditar(amb2, usuario=PROFISSIONAL.id, chave="c2", carteira="profissional")
    assert recusado(alterar(amb2, "m1", valor_moeda_centavos=1), "creditos_vigentes")
    amb2.relogio.avancar(days=91)
    assert alterar(amb2, "m1", valor_moeda_centavos=1).status_code == 200


def test_sem_como_ler_o_saldo_a_piora_do_uso_e_recusada(amb2, monkeypatch):
    def quebrar(_):
        raise RuntimeError("tabela ausente")

    monkeypatch.setattr(amb2.contexto.moedas, "ha_saldo_vivo", quebrar)
    assert recusado(alterar(amb2, valor_moeda_centavos=1), "creditos_vigentes")


def test_programa_desligado_e_sem_saldo_ajusta_livre(amb2):
    amb2.contexto.moedas = MoedasEmMemoria(ConfigMoedas(**(CFG | {"ativo": False})))
    r = alterar(amb2, valor_moeda_centavos=1, bonus_avaliacao_moedas=1)
    assert r.status_code == 200, r.text


def test_dois_pedidos_ao_mesmo_tempo_usam_o_aviso_uma_vez(amb2):
    avisar(amb2, {"ativo": False})
    amb2.relogio.avancar(days=30)
    with ThreadPoolExecutor(2) as pool:
        respostas = list(pool.map(lambda _: alterar(amb2, "m1", ativo=False), range(2)))
    assert [r.status_code for r in respostas] == [200, 200]
    auditoria = amb2.admin.auditoria
    linhas = [x for x in auditoria._linhas if x["acao"] == "moedas.config_alterada"]
    assert sum("referencia" in str(x["depois"]) for x in linhas) == 1


def test_mudancas_so_no_aviso_dos_tratinhos_e_com_campo_conhecido(amb2):
    base = {"tipo": "tratinhos", "referencia": "x", "vigencia": dia(amb2, 30)}
    base["resumo"] = "Mudam regras do programa."
    for ruim in ({"nada": 1}, {}, {"ativo": "não"}):
        assert enviar(amb2, base | {"mudancas": ruim}).status_code == 422, ruim
    termos = base | {"tipo": "termos", "motivo": "Revisão jurídica feita."}
    termos |= {"link": "https://exemplo.invalid/t", "mudancas": {"ativo": False}}
    assert enviar(amb2, termos).status_code == 422
