"""Modalidade (presencial/remoto) contra o Postgres local descartável. Nunca toca no Supabase."""

from __future__ import annotations

from dataclasses import replace

import pytest

from trato.persistencia.profissionais import ProfissionaisPostgres

from .test_fluxo_postgres import corpo_pedido

pytestmark = pytest.mark.integracao


def _abertos(c, quem="profissional") -> set[str]:
    r = c.cliente.get("/v1/profissional/pedidos-abertos", headers=c.token(quem))
    assert r.status_code == 200, r.text
    return {p["id"]: p for p in r.json()}.keys()


def _remoto(c) -> str:
    corpo = corpo_pedido(c, modalidade="remoto", titulo="Montar o site")
    corpo.pop("endereco")  # remoto não precisa de endereço
    r = c.cliente.post("/v1/pedidos", json=corpo, headers=c.token("cliente"))
    assert r.status_code == 201, r.text
    assert r.json()["modalidade"] == "remoto"
    return r.json()["id"]


@pytest.fixture
def categoria_remota(cenario):
    """O profissional atua na categoria e na cidade do cenário; o remoto fica ligado nela."""
    with cenario.local.admin() as con:
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (cenario.ids["profissional"], cenario.categoria_id),
        )
        if not con.execute(
            "select 1 from public.profissional_regioes where profissional_id = %s",
            (cenario.ids["profissional"],),
        ).fetchone():
            con.execute(
                "insert into public.profissional_regioes (profissional_id, cidade_id) "
                "values (%s, %s)",
                (cenario.ids["profissional"], cenario.cidade_id),
            )
        con.execute(
            "update public.categorias set aceita_remoto = true where id = %s",
            (cenario.categoria_id,),
        )
    yield cenario
    with cenario.local.admin() as con:
        con.execute(
            "update public.categorias set aceita_remoto = false where id = %s",
            (cenario.categoria_id,),
        )


def test_remoto_recusado_enquanto_a_categoria_nao_aceita(cenario):
    corpo = corpo_pedido(cenario, modalidade="remoto")
    corpo.pop("endereco")
    r = cenario.cliente.post("/v1/pedidos", json=corpo, headers=cenario.token("cliente"))
    assert r.status_code == 422 and "não atende de forma remota" in r.json()["detail"]


def test_presencial_sem_endereco_completo_e_recusado(cenario):
    corpo = corpo_pedido(cenario)
    corpo["endereco"] = {"logradouro": "Rua A"}
    r = cenario.cliente.post("/v1/pedidos", json=corpo, headers=cenario.token("cliente"))
    assert r.status_code == 422 and "falta" in r.json()["detail"]


def test_catalogo_publico_diz_quais_categorias_aceitam_remoto(categoria_remota):
    c = categoria_remota
    cats = c.cliente.get("/v1/catalogo/categorias", headers=c.token("cliente")).json()
    por_id = {x["id"]: x for x in cats}
    assert por_id[c.categoria_id]["aceita_remoto"] is True


def test_profissional_so_presencial_nao_ve_pedido_remoto_e_o_remoto_ve(categoria_remota):
    c = categoria_remota
    pedido = _remoto(c)
    repo = ProfissionaisPostgres(c.banco)
    perfil = repo.obter(c.ids["profissional"])
    assert perfil.atende_presencial and not perfil.atende_remoto  # padrão dos cadastros
    assert pedido not in _abertos(c)
    try:
        repo.salvar(replace(perfil, atende_remoto=True))
        assert pedido in _abertos(c)
        # só remoto: vê o remoto (de qualquer cidade), mas não os presenciais
        presencial = c.cliente.post(
            "/v1/pedidos", json=corpo_pedido(c), headers=c.token("cliente")
        ).json()["id"]
        assert presencial in _abertos(c)
        repo.salvar(replace(perfil, atende_presencial=False, atende_remoto=True))
        vistos = _abertos(c)
        assert pedido in vistos and presencial not in vistos
    finally:
        repo.salvar(perfil)


def test_perfil_guarda_o_que_o_profissional_atende(cenario):
    repo = ProfissionaisPostgres(cenario.banco)
    perfil = repo.obter(cenario.ids["profissional"])
    try:
        repo.salvar(replace(perfil, atende_presencial=True, atende_remoto=True))
        de_novo = repo.obter(cenario.ids["profissional"])
        assert de_novo.atende_presencial and de_novo.atende_remoto
    finally:
        repo.salvar(perfil)


def test_banco_nao_deixa_profissional_sem_nenhuma_modalidade(cenario):
    import psycopg

    with cenario.local.admin() as con:
        with pytest.raises(psycopg.errors.CheckViolation):
            con.execute(
                "update public.perfis_profissional set atende_presencial = false, "
                "atende_remoto = false where usuario_id = %s",
                (cenario.ids["profissional"],),
            )


def test_modalidade_do_pedido_nao_muda_depois_de_criado(cenario):
    import psycopg

    pid = corpo = None
    r = cenario.cliente.post(
        "/v1/pedidos", json=corpo_pedido(cenario), headers=cenario.token("cliente")
    )
    pid = r.json()["id"]
    with cenario.local.admin() as con:
        with pytest.raises(psycopg.errors.RestrictViolation):
            con.execute("update public.pedidos set modalidade = 'remoto' where id = %s", (pid,))
