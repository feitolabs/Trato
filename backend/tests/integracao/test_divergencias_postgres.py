"""Cadastro, catálogo e busca de profissionais contra o Postgres local descartável (pgserver).
Nunca toca no Supabase real."""

from __future__ import annotations

import uuid

import pytest

from .pg_local import RAIZ

pytestmark = pytest.mark.integracao


@pytest.fixture(scope="module")
def mundo(cenario):
    c = cenario
    with c.local.admin() as con:
        # Disponibilidade/portfólio e `upload_solicitacoes` (já aplicadas no Supabase) não fazem
        # parte do banco descartável base: aplica só aqui.
        if con.execute("select to_regclass('public.upload_solicitacoes')").fetchone()[0] is None:
            migration = (
                RAIZ
                / "supabase/migrations/20261030130000_profissional_disponibilidade_portfolio_uploads.sql"
            )
            con.execute(migration.read_text("utf-8"))
        c.cat_eletrica = str(
            con.execute(
                "insert into public.categorias (nome, slug, ordem) "
                "values ('Elétrica', 'eletrica-busca', 5) returning id"
            ).fetchone()[0]
        )
        c.cat_inativa = str(
            con.execute(
                "insert into public.categorias (nome, slug, ativa) "
                "values ('Antiga', 'antiga-busca', false) returning id"
            ).fetchone()[0]
        )
        c.cidade_b = str(
            con.execute(
                "insert into public.cidades (nome, uf, ativa) values ('Betim', 'MG', true) "
                "returning id"
            ).fetchone()[0]
        )
        c.cidade_inativa = str(
            con.execute(
                "insert into public.cidades (nome, uf, ativa) values ('Fechada', 'MG', false) "
                "returning id"
            ).fetchone()[0]
        )
        nomes = {
            "ana_pro": "Ana Paula Ferreira",
            "bia_pro": "Bia Costa",
            "caio_pro": "Caio Nunes",
            "cli_busca": "Cliente Busca",
        }
        for nome, completo in nomes.items():
            c.ids[nome] = str(uuid.uuid4())
            con.execute("insert into auth.users (id) values (%s)", (c.ids[nome],))
            con.execute(
                "insert into public.usuarios (id, nome) values (%s, %s)", (c.ids[nome], completo)
            )
    return c


def get(c, url, quem="cli_busca"):
    return c.cliente.get(url, headers=c.token(quem))


def cadastrar(c, quem, **extra):
    corpo = {
        "categorias": [c.cat_eletrica],
        "regioes": [{"cidade_id": c.cidade_b, "bairro": "Centro"}],
        "bio": "Instalações e reparos.",
        **extra,
    }
    return c.cliente.post("/v1/profissional/cadastro", json=corpo, headers=c.token(quem))


def aprovar(c, quem, nota=None, servicos=0):
    with c.local.admin() as con:
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', "
            "nivel_verificacao = 'verificado', nota_publica = %s, servicos_concluidos = %s "
            "where usuario_id = %s",
            (nota, servicos, c.ids[quem]),
        )


def nomes_de(r):
    return [i["nome"] for i in r.json()["itens"]]


def test_catalogo_so_ativos_e_exige_login(mundo):
    c = mundo
    assert c.cliente.get("/v1/catalogo/categorias").status_code == 401
    cats = get(c, "/v1/catalogo/categorias").json()
    ids = {x["id"] for x in cats}
    assert c.cat_eletrica in ids and c.categoria_id in ids and c.cat_inativa not in ids
    cidades = get(c, "/v1/catalogo/cidades").json()
    por_id = {x["id"]: x for x in cidades}
    assert por_id[c.cidade_b] == {"id": c.cidade_b, "nome": "Betim", "uf": "MG"}
    assert c.cidade_inativa not in por_id


def test_cadastro_grava_no_banco_e_so_aprovado_aparece_na_busca(mundo):
    c = mundo
    r = cadastrar(c, "ana_pro", portfolio=[{"titulo": "Quadro novo"}])
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "em_analise"
    # categoria ou cidade inativa: recusado
    assert cadastrar(c, "bia_pro", categorias=[c.cat_inativa]).status_code == 422
    inativa = cadastrar(c, "bia_pro", regioes=[{"cidade_id": c.cidade_inativa}])
    assert inativa.status_code == 422
    assert get(c, "/v1/profissionais?servico=eletrica").json()["itens"] == []  # ainda em análise
    aprovar(c, "ana_pro", nota=4.8, servicos=12)
    r = get(c, "/v1/profissionais?servico=ELÉTRICA")
    [item] = r.json()["itens"]
    assert item["id"] == c.ids["ana_pro"] and item["nome"] == "Ana F."
    assert item["nota_publica"] == 4.8 and item["servicos_concluidos"] == 12
    assert item["categorias"] == [c.cat_eletrica] and r.json()["total"] == 1
    # perfil lido de volta (portfólio e região) e o público com cidades
    meu = get(c, "/v1/profissional/perfil", "ana_pro").json()
    assert meu["portfolio"] == [{"titulo": "Quadro novo", "descricao": None}]
    assert meu["regioes"] == [{"cidade_id": c.cidade_b, "bairro": "Centro"}]
    pub = get(c, f"/v1/profissionais/{c.ids['ana_pro']}").json()
    assert pub["cidades"] == ["Betim/MG"] and pub["no_trato_desde"]


def test_filtros_de_bairro_cidade_ordem_e_suspensao(mundo):
    c = mundo
    assert cadastrar(c, "bia_pro", regioes=[{"cidade_id": c.cidade_b}]).status_code == 201
    icaivera = cadastrar(c, "caio_pro", regioes=[{"cidade_id": c.cidade_b, "bairro": "Icaivera"}])
    assert icaivera.status_code == 201
    aprovar(c, "bia_pro", nota=4.9, servicos=3)
    aprovar(c, "caio_pro", nota=None, servicos=0)
    base = f"/v1/profissionais?categoria_id={c.cat_eletrica}"
    assert nomes_de(get(c, base)) == ["Bia C.", "Ana F.", "Caio N."]  # sem nota por último
    # bairro: Bia atende a cidade toda, Ana só o Centro, Caio só o Icaivera
    assert nomes_de(get(c, base + "&bairro=centro")) == ["Bia C.", "Ana F."]
    assert nomes_de(get(c, base + "&bairro=Icaivera")) == ["Bia C.", "Caio N."]
    assert nomes_de(get(c, base + "&bairro=Outro")) == ["Bia C."]
    assert get(c, base + f"&cidade_id={c.cidade_inativa}").json()["itens"] == []
    assert get(c, base + "&cidade_id=nao-e-uuid").json()["total"] == 0
    pag = get(c, base + "&limite=2&pagina=2").json()
    assert nomes_de(get(c, base + "&limite=2&pagina=2")) == ["Caio N."]
    assert pag["tem_mais"] is False and pag["total"] == 3
    # suspender o cadastro tira da busca; a edição do perfil não devolve o acesso
    with c.local.admin() as con:
        con.execute(
            "update public.perfis_profissional set status = 'suspenso' where usuario_id = %s",
            (c.ids["bia_pro"],),
        )
    assert "Bia C." not in nomes_de(get(c, base))
    r = c.cliente.patch(
        "/v1/profissional/perfil", json={"bio": "Nova bio"}, headers=c.token("bia_pro")
    )
    assert r.status_code == 200 and r.json()["status"] == "suspenso"


def test_busca_nao_vaza_dado_pessoal(mundo):
    c = mundo
    with c.local.admin() as con:
        con.execute(
            "insert into public.usuarios_privados (usuario_id, cpf, telefone) "
            "values (%s, '123.456.789-09', '+5531999990000') on conflict do nothing",
            (c.ids["ana_pro"],),
        )
    texto = get(c, "/v1/profissionais").text
    assert "123.456" not in texto and "99999" not in texto and "Paula" not in texto


def test_editar_perfil_troca_categorias_e_regioes_no_banco(mundo):
    c = mundo
    r = c.cliente.patch(
        "/v1/profissional/perfil",
        json={"categorias": [c.categoria_id], "regioes": [{"cidade_id": c.cidade_id}]},
        headers=c.token("ana_pro"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["categorias"] == [c.categoria_id]
    ids = [
        i["id"] for i in get(c, f"/v1/profissionais?categoria_id={c.cat_eletrica}").json()["itens"]
    ]
    assert c.ids["ana_pro"] not in ids


def test_migration_nova_do_destino_portfolio_aplica_e_desfaz(mundo):
    """A migration NOVA (não aplicada no Supabase) funciona no banco descartável, com rollback."""
    c = mundo
    nova = (RAIZ / "supabase/migrations/20261030140000_upload_destino_portfolio.sql").read_text(
        "utf-8"
    )
    volta = (RAIZ / "supabase/rollback/upload_destino_portfolio_rollback.sql").read_text("utf-8")
    inserir = (
        "insert into public.upload_solicitacoes (dono_id, destino, bucket, caminho, content_type, "
        "tamanho_bytes) values (%s, 'portfolio', 'avatar', %s, 'image/jpeg', 10)"
    )
    with c.local.admin() as con:
        con.execute(nova)
        con.execute(inserir, (c.ids["ana_pro"], f"{c.ids['ana_pro']}/portfolio/a.jpg"))
        con.execute("delete from public.upload_solicitacoes")  # superusuário do banco descartável
        con.execute(volta)
        with pytest.raises(Exception, match="upload_solicitacoes_destino_check"):
            con.execute(inserir, (c.ids["ana_pro"], f"{c.ids['ana_pro']}/portfolio/b.jpg"))
