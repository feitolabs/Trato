"""B27: elogios em tags (lista fechada, até 3, só cliente -> profissional) e `etiquetas_top`."""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, cab
from test_profissional_upload import _aprovar, e2  # noqa: F401

from trato.api.elogios import ETIQUETAS_ELOGIO, canonica, etiquetas_top
from trato.api.repositorios_app import Avaliacao
from trato.pedidos.estados import Estado

AVALIAR = "/v1/pedidos/ped-1/avaliacao"
AVALIAR_CONTRATO = "/v1/contratos/ped-1/avaliacao"


def _avaliar(amb, quem="t-cliente", url=AVALIAR, **corpo):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    return amb.cliente.post(url, json={"nota_geral": 5, **corpo}, headers=cab(quem))


def test_aceita_etiquetas_validas_normaliza_e_aceita_lista_vazia(amb):
    r = _avaliar(amb, etiquetas=["  pontual ", "EXPLICOU   BEM", "preço justo"])
    assert r.status_code == 201, r.text
    assert r.json()["etiquetas"] == ["Pontual", "Explicou bem", "Preço justo"]


def test_lista_vazia_continua_valida(amb):
    assert _avaliar(amb, etiquetas=[]).json()["etiquetas"] == []


def test_alias_de_contratos_segue_a_mesma_regra(amb):
    assert _avaliar(amb, url=AVALIAR_CONTRATO, etiquetas=["Limpo"]).status_code == 201


@pytest.mark.parametrize("url", [AVALIAR, AVALIAR_CONTRATO])
def test_rejeita_fora_da_lista_mais_de_tres_e_repetida(amb, url):
    fora = _avaliar(amb, url=url, etiquetas=["Rápido"])
    assert fora.status_code == 422 and "Pontual" in fora.json()["detail"]
    assert _avaliar(amb, url=url, etiquetas=list(ETIQUETAS_ELOGIO[:4])).status_code == 422
    rep = _avaliar(amb, url=url, etiquetas=["Limpo", " limpo"])
    assert rep.status_code == 422 and "repetida" in rep.json()["detail"]
    assert _avaliar(amb, url=url, etiquetas=list(ETIQUETAS_ELOGIO[:3])).status_code == 201


def test_profissional_avaliando_cliente_nao_pode_mandar_etiquetas(amb):
    r = _avaliar(amb, quem="t-prof", etiquetas=["Pontual"])
    assert r.status_code == 422
    ok = _avaliar(amb, quem="t-prof", etiquetas=[])
    assert ok.status_code == 201 and ok.json()["etiquetas"] == []


def test_duplo_toque_com_o_mesmo_corpo_segue_idempotente(amb):
    assert _avaliar(amb, etiquetas=["pontual"]).status_code == 201
    outra = amb.cliente.post(
        AVALIAR, json={"nota_geral": 5, "etiquetas": ["Pontual"]}, headers=cab("t-cliente")
    )
    assert outra.status_code == 200


def test_canonica():
    assert canonica("  caprichoso ") == "Caprichoso" and canonica("Rápido") is None


def _av(i, etiquetas, direcao="cliente_para_profissional", autor="cli-secreto"):
    return Avaliacao(
        f"ped-{i}", direcao, autor, "pro-1", 5, None, tuple(etiquetas), AGORA + timedelta(days=i)
    )


def test_etiquetas_top_conta_ordena_limita_a_tres_e_ignora_texto_livre():
    avs = [
        _av(1, ["Pontual", "Limpo"]),
        _av(2, ["Pontual", "Educado"]),
        _av(3, ["pontual", "Limpo", "Caprichoso"]),
        _av(4, ["Educado"]),
        _av(5, ["liga 31 98888-7777"]),  # legado fora da lista
    ]
    assert etiquetas_top(avs) == [
        {"etiqueta": "Pontual", "total": 3},
        {"etiqueta": "Educado", "total": 2},
        {"etiqueta": "Limpo", "total": 2},
    ]
    assert etiquetas_top([]) == []


def test_perfil_devolve_etiquetas_top_so_contagem_e_so_do_cliente(e2):  # noqa: F811
    _aprovar(e2)
    av = e2.amb.contexto.avaliacoes
    av.salvar(_av(1, ["Pontual", "Limpo"]))
    av.salvar(_av(2, ["Pontual"]))
    av.salvar(_av(3, ["Caprichoso"], direcao="profissional_para_cliente"))  # outro lado: não conta
    r = e2.get("/v1/profissionais/pro-1", "t-cliente")
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["etiquetas_top"] == [
        {"etiqueta": "Pontual", "total": 2},
        {"etiqueta": "Limpo", "total": 1},
    ]
    assert all(set(x) == {"etiqueta", "total"} for x in corpo["etiquetas_top"])
    assert "cli-secreto" not in str(corpo["etiquetas_top"])


def test_perfil_sem_avaliacoes_tem_etiquetas_top_vazia(e2):  # noqa: F811
    _aprovar(e2)
    assert e2.get("/v1/profissionais/pro-1", "t-cliente").json()["etiquetas_top"] == []
