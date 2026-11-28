"""BE-TETO75-MINIMO123: antecedência de reagendamento com teto de 24 h (7.5) e nota só com o
mínimo de avaliações (12.3). Memória."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace

import pytest
from conftest import cab
from test_divergencias_busca import busca, ids, ver  # noqa: F401 - fixture

from trato.api.regra_contratada import regra_do_contrato
from trato.api.repositorios import Contrato
from trato.api.rotas_reagendamento import _antecedencia_horas
from trato.pedidos.estados import Estado
from trato.profissional.nota import minimo_de_avaliacoes, nota_visivel

CHAVE = "reagendamento_antecedencia_horas"


@pytest.mark.parametrize(
    ("publicado", "congelado", "esperado"),
    [(None, None, 24), (48, None, 24), (6, None, 6), (48, 72, 24), (48, 12, 12), (6, 48, 6)],
)
def test_antecedencia_nunca_passa_de_24_horas(amb, publicado, congelado, esperado):
    amb.semear_pedido(Estado.AGENDADO)
    if publicado is not None:
        amb.contexto.config.parametros[CHAVE] = publicado
    regras = {"parametros": {} if congelado is None else {CHAVE: congelado}}
    amb.contexto.contratos._itens["ped-1"] = Contrato("ped-1", "orc-1", "pro", 1, regras=regras)
    assert _antecedencia_horas(amb.contexto, "ped-1") == esperado
    amb.contexto.contratos._itens.clear()  # sem contrato: também com o teto
    assert _antecedencia_horas(amb.contexto, "ped-1") == min(publicado or 24, 24)
    assert regra_do_contrato(None, CHAVE, "menor", 100) == 24


@pytest.mark.parametrize("publicado", [None, 0, -3, 1])
def test_sem_parametro_ou_invalido_o_minimo_e_1(amb, publicado):
    if publicado is not None:
        amb.contexto.config.parametros["nota_minimo_avaliacoes"] = publicado
    assert minimo_de_avaliacoes(amb.contexto.config) == 1
    assert nota_visivel(4.8, 0, 1) == 4.8  # comportamento de sempre


def totais(amb, **quantos) -> None:
    for uid, total in quantos.items():
        atual = amb.contexto.usuarios.detalhe(uid)
        amb.contexto.usuarios.adicionar(replace(atual, avaliacoes_total=total))


def itens(amb, url="/v1/profissionais"):
    return {i["id"]: i for i in ver(amb, url).json()["itens"]}


def test_abaixo_do_minimo_a_nota_nao_sai_nao_filtra_e_nao_ordena(amb, busca):
    totais(amb, p1=2, p2=3)
    antes = itens(amb)
    assert (antes["p1"]["nota_publica"], antes["p1"]["nota_minimo_avaliacoes"]) == (4.9, 1)
    assert ids(ver(amb, "/v1/profissionais?nota_minima=4.8")) == ["p1"]
    amb.contexto.config.parametros["nota_minimo_avaliacoes"] = 3
    depois = itens(amb)
    assert (depois["p1"]["nota_publica"], depois["p1"]["avaliacoes_total"]) == (None, 2)
    assert (depois["p2"]["nota_publica"], depois["p2"]["avaliacoes_total"]) == (4.5, 3)
    assert depois["p1"]["nota_minimo_avaliacoes"] == 3
    assert ids(ver(amb, "/v1/profissionais?nota_minima=4.8")) == []
    assert ids(ver(amb, "/v1/profissionais?nota_minima=4.0")) == ["p2"]
    # Ordem do aviso de pedido novo: a nota oculta de p1 (4,9) não o coloca na frente.
    elegiveis = busca.repo.listar_elegiveis_para_pedido(
        "c-pint", "bh", detalhe=amb.contexto.usuarios.detalhe, nota_minimo_avaliacoes=3
    )
    assert elegiveis == ["p2", "p1"]


def test_perfil_publico_site_perfil_do_app_e_favoritos(amb, busca):
    totais(amb, p1=2)
    amb.contexto.config.parametros["nota_minimo_avaliacoes"] = 3
    app = ver(amb, "/v1/profissionais/p1").json()
    assert (app["nota_publica"], app["avaliacoes_total"], app["nota_minimo_avaliacoes"]) == (
        None,
        2,
        3,
    )
    site = amb.cliente.get("/v1/publico/profissionais/p1")
    assert site.status_code == 200, site.text
    assert (site.json()["nota_media"], site.json()["avaliacoes_total"]) == (None, 2)
    assert site.json()["nota_minimo_avaliacoes"] == 3
    amb.contexto.conta.favoritos = lambda _id: [
        __import__("trato.api.conta", fromlist=["Favorito"]).Favorito("p1", "Maria", 4.9, 30, 2)
    ]
    (favorito,) = amb.cliente.get("/v1/me/favoritos", headers=cab("t-cliente")).json()
    assert (favorito["nota_publica"], favorito["avaliacoes_total"]) == (None, 2)
    totais(amb, p1=3)
    assert ver(amb, "/v1/profissionais/p1").json()["nota_publica"] == 4.9
