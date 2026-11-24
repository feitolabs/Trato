"""Filtro `disponivel_agora` em GET /v1/profissionais."""

from __future__ import annotations

from conftest import AGORA, cab

from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.profissional.repositorio import PerfilProfissional, Regiao


def _semear(amb):
    modulo = modulo_em_memoria(amb.cliente.app)
    modulo.catalogo.categorias.update({"c-ar": "ar-condicionado"})
    modulo.catalogo.nomes.update({"c-ar": "Ar-condicionado", "div": "Divinópolis"})
    modulo.catalogo.cidades.update({"div"})
    modulo.catalogo.ufs.update({"div": "MG"})
    for uid, status, disponivel in (
        ("pro-on", "aprovado", True),
        ("pro-off", "aprovado", False),
        ("pro-pendente", "pendente", True),
    ):
        modulo.repo.salvar(
            PerfilProfissional(
                uid, status, "Instalação de ar.", ("c-ar",), (Regiao("div", "Centro"),), (), (),
                AGORA, disponivel_agora=disponivel,
            )
        )  # fmt: skip


def _ids(amb, query=""):
    r = amb.cliente.get(f"/v1/profissionais{query}", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    return {i["id"]: i for i in r.json()["itens"]}


def test_filtro_traz_so_aprovados_disponiveis(amb):
    _semear(amb)
    itens = _ids(amb, "?disponivel_agora=true")
    assert set(itens) == {"pro-on"}
    assert itens["pro-on"]["disponivel_agora"] is True


def test_sem_o_filtro_ou_false_mantem_o_comportamento(amb):
    _semear(amb)
    for query in ("", "?disponivel_agora=false"):
        itens = _ids(amb, query)
        assert set(itens) == {"pro-on", "pro-off"}
        assert itens["pro-off"]["disponivel_agora"] is False
