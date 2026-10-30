"""Catálogo público (categorias e cidades) e busca de profissionais (memória)."""

from __future__ import annotations

import pytest
from conftest import AGORA, cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.profissional.repositorio import PerfilProfissional, Regiao


@pytest.fixture
def busca(amb):
    modulo = modulo_em_memoria(amb.cliente.app)
    modulo.catalogo.categorias.update(
        {"c-pint": "pintura", "c-elet": "eletrica", "c-enc": "encanador"}
    )
    modulo.catalogo.nomes.update({"c-pint": "Pintura", "c-elet": "Elétrica", "c-enc": "Encanador"})
    modulo.catalogo.cidades.update({"bh", "sp"})
    modulo.catalogo.nomes.update({"bh": "Belo Horizonte", "sp": "São Paulo"})
    modulo.catalogo.ufs.update({"bh": "MG", "sp": "SP"})

    def novo(uid, nome, status, cats, regioes, nota=None, servicos=0):
        modulo.repo.salvar(
            PerfilProfissional(
                uid, status, "Atendo com cuidado.", tuple(cats), tuple(regioes), (), (), AGORA
            )
        )
        amb.contexto.usuarios.adicionar(
            PerfilDetalhe(
                uid, nome, PapelUsuario.PROFISSIONAL, "ativo", "verificado", nota, servicos
            )
        )

    novo("p1", "Maria Aparecida Souza", "aprovado", ["c-pint"], [Regiao("bh", "Savassi")], 4.9, 30)
    novo("p2", "João Lima", "aprovado", ["c-pint", "c-elet"], [Regiao("bh")], 4.5, 80)
    novo("p3", "Ana Reis", "aprovado", ["c-elet"], [Regiao("sp", "Moema")], None, 0)
    novo("p4", "Pedro Em Analise", "em_analise", ["c-pint"], [Regiao("bh", "Savassi")], 5.0, 99)
    novo("p5", "Rui Suspenso", "suspenso", ["c-pint"], [Regiao("bh")], 5.0, 99)
    return modulo


def ver(amb, url, quem="t-cliente"):
    return amb.cliente.get(url, headers=cab(quem))


def ids(r):
    return [i["id"] for i in r.json()["itens"]]


def test_catalogo_exige_login_e_lista_so_o_ativo(amb, busca):
    assert amb.cliente.get("/v1/catalogo/categorias").status_code == 401
    assert amb.cliente.get("/v1/catalogo/cidades").status_code == 401
    cats = ver(amb, "/v1/catalogo/categorias").json()
    assert [c["nome"] for c in cats] == ["Elétrica", "Encanador", "Pintura"]
    assert {"id", "nome", "slug", "icone", "pai_id"} == set(cats[0])
    cidades = ver(amb, "/v1/catalogo/cidades", "t-prof").json()
    assert [(c["nome"], c["uf"]) for c in cidades] == [
        ("Belo Horizonte", "MG"),
        ("São Paulo", "SP"),
    ]
    assert ver(amb, "/v1/catalogo/cidades", "t-equipe").status_code == 200  # dado público


def test_busca_so_aprovados_ordenada_e_sem_dado_pessoal(amb, busca):
    r = ver(amb, "/v1/profissionais")
    assert r.status_code == 200
    assert ids(r) == ["p1", "p2", "p3"]  # melhor nota primeiro; sem nota por último
    corpo = r.json()
    assert corpo["total"] == 3 and corpo["tem_mais"] is False and corpo["pagina"] == 1
    p1 = next(i for i in corpo["itens"] if i["id"] == "p1")
    assert p1["nome"] == "Maria S."  # abreviado
    assert set(p1) == {
        "id", "nome", "bio", "nivel_verificacao", "nota_publica", "servicos_concluidos", "categorias",
    }  # fmt: skip
    assert "Aparecida" not in r.text and "cpf" not in r.text.lower()


def test_busca_por_servico_categoria_e_bairro(amb, busca):
    assert ids(ver(amb, "/v1/profissionais?servico=pintura")) == ["p1", "p2"]
    assert ids(ver(amb, "/v1/profissionais?servico=ELETRICA")) == ["p2", "p3"]  # sem acento/caixa
    assert ids(ver(amb, "/v1/profissionais?servico=elétr")) == ["p2", "p3"]
    assert ids(ver(amb, "/v1/profissionais?servico=jardinagem")) == []
    assert ids(ver(amb, "/v1/profissionais?categoria_id=c-elet")) == ["p2", "p3"]
    assert ids(ver(amb, "/v1/profissionais?servico=pintura&categoria_id=c-elet")) == []
    # bairro: quem fixou o bairro e quem atende a cidade toda
    assert ids(ver(amb, "/v1/profissionais?bairro=savassi")) == ["p1", "p2"]
    assert ids(ver(amb, "/v1/profissionais?bairro=Moema")) == ["p2", "p3"]
    assert ids(ver(amb, "/v1/profissionais?cidade_id=sp")) == ["p3"]
    assert ids(ver(amb, "/v1/profissionais?cidade_id=bh&bairro=Lourdes")) == ["p2"]


def test_busca_paginada_e_validada(amb, busca):
    a = ver(amb, "/v1/profissionais?limite=2&pagina=1").json()
    b = ver(amb, "/v1/profissionais?limite=2&pagina=2").json()
    assert [i["id"] for i in a["itens"]] == ["p1", "p2"] and a["tem_mais"] is True
    assert [i["id"] for i in b["itens"]] == ["p3"] and b["tem_mais"] is False and b["total"] == 3
    assert ver(amb, "/v1/profissionais?limite=51").status_code == 422
    assert ver(amb, "/v1/profissionais?pagina=0").status_code == 422
    assert ver(amb, "/v1/profissionais?servico=a").status_code == 422
    assert amb.cliente.get("/v1/profissionais").status_code == 401
    assert ver(amb, "/v1/profissionais", "t-equipe").status_code == 403
    assert ver(amb, "/v1/profissionais", "t-prof").status_code == 200


def test_perfil_publico_traz_no_trato_desde_e_cidades(amb, busca):
    r = ver(amb, "/v1/profissionais/p1")
    assert r.status_code == 200
    assert r.json()["no_trato_desde"].startswith("2026-10-29")
    assert r.json()["cidades"] == ["Belo Horizonte/MG"]
    assert ver(amb, "/v1/profissionais/p4").status_code == 404  # em análise não aparece
