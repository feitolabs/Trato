"""Painel: orçamento de desconto das moedas (GET /orcamento) e os 3 campos novos da config."""

from __future__ import annotations

from datetime import date

from trato.api.moedas import ConfigMoedas, MoedasEmMemoria, dia_ref, mes_ref


def _preparar(painel, **cfg) -> MoedasEmMemoria:
    contexto = painel.ambiente.contexto
    contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))
    return contexto.moedas


def test_orcamento_exige_login_e_devolve_o_contrato(painel):
    assert painel.chamar(None, "GET", "/v1/admin/moedas/orcamento").status_code == 401
    repo = _preparar(painel, orcamento_mensal_desconto_centavos=30_000, aviso_percentual=80)
    mes = mes_ref(painel.ambiente.contexto.agora())
    dia = dia_ref(painel.ambiente.contexto.agora())

    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/orcamento")
    assert r.status_code == 200, r.text
    assert r.json() == {
        "mes_ref": mes.isoformat(),
        "orcamento_centavos": 30_000,
        "usado_centavos": 0,
        "percentual_usado": 0.0,
        "aviso": False,
        "dia_ref": dia.isoformat(),
        "usado_dia_centavos": 0,
        "teto_dia_centavos": 1_000,
    }

    dia = dia_ref(painel.ambiente.contexto.agora())
    repo.reservar_orcamento(mes, dia, 800, 30_000, 1_000)
    repo.reservar_orcamento(mes, date(2026, 1, 1), 23_200, 30_000, 99_000)  # outro dia: 80% no mês
    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/orcamento").json()
    assert (r["usado_centavos"], r["percentual_usado"], r["aviso"]) == (24_000, 80.0, True)
    assert (r["usado_dia_centavos"], r["teto_dia_centavos"]) == (800, 1_000)


def test_aviso_fica_desligado_abaixo_do_percentual(painel):
    repo = _preparar(painel, orcamento_mensal_desconto_centavos=30_000, aviso_percentual=80)
    mes = mes_ref(painel.ambiente.contexto.agora())
    dia = dia_ref(painel.ambiente.contexto.agora())
    repo.reservar_orcamento(mes, dia, 23_999, 30_000, 99_000)
    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/orcamento").json()
    assert r["aviso"] is False


def test_config_traz_os_campos_novos_e_put_audita(painel):
    _preparar(painel)
    r = painel.chamar("administrador", "GET", "/v1/admin/moedas/config").json()
    assert r["orcamento_mensal_desconto_centavos"] == 30_000
    assert r["aviso_percentual"] == 80
    assert r["teto_desconto_cliente_mes_centavos"] == 500
    assert r["teto_diario_desconto_centavos"] == 1_000
    assert r["dias_liberacao_bonus"] == 7

    corpo = {
        "ativo": True,
        "bonus_avaliacao_moedas": 50,
        "valor_moeda_centavos": 1,
        "teto_mensal_moedas": 500,
        "min_servico_centavos": 5000,
        "max_bonus_por_profissional_mes": 1,
        "max_desconto_percentual": 20,
        "validade_dias": None,
        "orcamento_mensal_desconto_centavos": 50_000,
        "aviso_percentual": 70,
        "teto_desconto_cliente_mes_centavos": 800,
        "teto_diario_desconto_centavos": 1_200,
        "dias_liberacao_bonus": 10,
        "motivo": "Ajuste do orçamento do mês",
    }
    r = painel.chamar("administrador", "PUT", "/v1/admin/moedas/config", json=corpo)
    assert r.status_code == 200, r.text
    assert r.json()["orcamento_mensal_desconto_centavos"] == 50_000
    assert painel.ambiente.contexto.moedas.config().teto_desconto_cliente_mes_centavos == 800
    assert r.json()["teto_diario_desconto_centavos"] == 1_200
    assert r.json()["dias_liberacao_bonus"] == 10

    # Sem os campos novos o PUT mantém o valor atual (não volta ao padrão).
    for campo in (
        "orcamento_mensal_desconto_centavos",
        "aviso_percentual",
        "teto_desconto_cliente_mes_centavos",
        "teto_diario_desconto_centavos",
        "dias_liberacao_bonus",
    ):
        corpo.pop(campo)
    corpo["motivo"] = "Só o bônus de avaliação mudou"
    r = painel.chamar("administrador", "PUT", "/v1/admin/moedas/config", json=corpo)
    assert r.status_code == 200, r.text
    assert r.json()["orcamento_mensal_desconto_centavos"] == 50_000
    assert r.json()["aviso_percentual"] == 70
    assert r.json()["teto_diario_desconto_centavos"] == 1_200
    assert r.json()["dias_liberacao_bonus"] == 10

    # Valor inválido é recusado e sem motivo também.
    ruim = {**corpo, "aviso_percentual": 101}
    assert (
        painel.chamar("administrador", "PUT", "/v1/admin/moedas/config", json=ruim).status_code
        == 422
    )
    sem_motivo = {k: v for k, v in corpo.items() if k != "motivo"}
    assert (
        painel.chamar(
            "administrador", "PUT", "/v1/admin/moedas/config", json=sem_motivo
        ).status_code
        == 422
    )
