# ruff: noqa: F811
"""BE-CATEGORIAS-36 (Termos 3.6): expor `incluido` e `nao_incluido` em GET /v1/catalogo/categorias,
com padrão [] em memória e recuo seguro quando as colunas ainda não existem no Postgres."""

from __future__ import annotations

from contextlib import contextmanager

from conftest import cab
from test_divergencias_busca import busca  # noqa: F401

from trato.persistencia.profissionais import CatalogoPostgres


def test_catalogo_categorias_expoe_incluido_e_nao_incluido_com_padrao_vazio(amb, busca):
    r = amb.cliente.get("/v1/catalogo/categorias", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    cats = r.json()
    assert cats
    for item in cats:
        assert item["incluido"] == []
        assert item["nao_incluido"] == []


def test_catalogo_categorias_em_memoria_retorna_listas_configuradas(amb, busca):
    catalogo = busca.catalogo
    cat_id = next(iter(catalogo.categorias))
    catalogo.incluido[cat_id] = ["Troca de tomada", "Instalação de chuveiro"]
    catalogo.nao_incluido[cat_id] = ["Compra de material", "Quebra de parede"]

    r = amb.cliente.get("/v1/catalogo/categorias", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    item = next(c for c in r.json() if c["id"] == cat_id)
    assert item["incluido"] == ["Troca de tomada", "Instalação de chuveiro"]
    assert item["nao_incluido"] == ["Compra de material", "Quebra de parede"]


class _CursorFake:
    def __init__(self, linhas):
        self._linhas = linhas

    def fetchall(self):
        return self._linhas


class _ConexaoFake:
    def __init__(self, linhas):
        self._linhas = linhas
        self.ultimo_sql = ""

    def execute(self, sql, *_args):
        self.ultimo_sql = sql
        return _CursorFake(self._linhas)


class _BancoFake:
    def __init__(self, linhas):
        self.con = _ConexaoFake(linhas)

    @contextmanager
    def transacao(self):
        yield self.con


def test_catalogo_postgres_cai_no_padrao_vazio_sem_colunas_e_le_quando_presentes():
    banco = _BancoFake(
        [
            {
                "id": "cat-1",
                "nome": "Elétrica",
                "slug": "eletrica",
                "icone": "bolt",
                "pai_id": None,
                "aceita_remoto": False,
                "incluido": None,
                "nao_incluido": None,
            },
            {
                "id": "cat-2",
                "nome": "Hidráulica",
                "slug": "hidraulica",
                "icone": None,
                "pai_id": None,
                "aceita_remoto": False,
                "incluido": ["Troca de torneira", "Desentupimento simples"],
                "nao_incluido": ["Substituição de tubulação interna"],
            },
        ]
    )
    cats = CatalogoPostgres(banco).categorias_publicas()
    assert "to_jsonb(c) -> 'incluido'" in banco.con.ultimo_sql
    assert "to_jsonb(c) -> 'nao_incluido'" in banco.con.ultimo_sql
    assert cats[0].incluido == () and cats[0].nao_incluido == ()
    assert cats[1].incluido == ("Troca de torneira", "Desentupimento simples")
    assert cats[1].nao_incluido == ("Substituição de tubulação interna",)
