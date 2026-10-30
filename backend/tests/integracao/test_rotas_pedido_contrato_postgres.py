"""Rotas em volta do orçamento e do contrato contra o Postgres local descartável: detalhe do
orçamento, perfil, pedidos abertos com filtros, recusa (migration NOVA, não aplicada no Supabase),
garantia, aditivos e nota de material. Nunca toca no Supabase real."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from trato.pedidos import estados
from trato.pedidos.estados import Ator, Papel, ProvaPagamento

from .pg_local import RAIZ
from .test_fluxo_postgres import abrir_pedido, acao, agora, enviar_orcamento, foto

pytestmark = pytest.mark.integracao


def get(c, url, quem, **kw):
    return c.cliente.get(url, headers=c.token(quem), **kw)


def post(c, url, quem, corpo=None, **kw):
    return c.cliente.post(url, json=corpo, headers=c.token(quem), **kw)


@pytest.fixture
def atuacao(cenario):
    c = cenario
    with c.local.admin() as con:
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (c.ids["profissional"], c.categoria_id),
        )
        if not con.execute(
            "select 1 from public.profissional_regioes where profissional_id = %s",
            (c.ids["profissional"],),
        ).fetchone():
            con.execute(
                "insert into public.profissional_regioes (profissional_id, cidade_id) "
                "values (%s, %s)",
                (c.ids["profissional"], c.cidade_id),
            )
    return c


@pytest.fixture(scope="module")
def com_recusas(cenario):
    """Aplica a migration NOVA (preparada, não aplicada no Supabase) só no banco descartável."""
    with cenario.local.admin() as con:
        if con.execute("select to_regclass('public.pedido_recusas')").fetchone()[0] is None:
            con.execute(
                (RAIZ / "supabase/migrations/20261030130000_pedido_recusas.sql").read_text("utf-8")
            )
    return cenario


def test_detalhe_do_orcamento_com_itens_validade_e_fora_do_escopo(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    orcamento_id = c.contexto.orcamentos.enviar(
        pedido_id=pedido_id,
        profissional_id=c.ids["profissional"],
        itens=[
            __import__("trato.persistencia.orcamentos", fromlist=["x"]).ItemOrcamento(
                "horas", "Mão de obra", __import__("decimal").Decimal("2.5"), 10_001
            ),
        ],
        agora=agora(),
        validade_ate=agora() + timedelta(days=3),
        fora_do_escopo="Não inclui massa corrida",
        prazo_execucao_dias=4,
    )
    r = get(c, f"/v1/orcamentos/{orcamento_id}", "cliente")
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["valor_centavos"] == 25_003  # 2,5 x 10.001 = 25.002,5 -> meio para cima
    assert corpo["fora_do_escopo"] == "Não inclui massa corrida" and corpo["validade_ate"]
    assert corpo["itens"][0]["descricao"] == "Mão de obra"
    assert corpo["itens"][0]["total_centavos"] == 25_003 and corpo["aceito"] is False
    assert corpo["profissional_nome"] == "profissional"
    assert get(c, f"/v1/orcamentos/{orcamento_id}", "profissional").status_code == 200
    # quem não é parte não vê; id lixo não vaza erro
    assert get(c, f"/v1/orcamentos/{orcamento_id}", "cliente2").status_code == 404
    assert get(c, f"/v1/orcamentos/{orcamento_id}", "profissional2").status_code == 404
    assert get(c, f"/v1/orcamentos/{uuid.uuid4()}", "cliente").status_code == 404
    assert get(c, "/v1/orcamentos/isto-nao-e-uuid", "cliente").status_code == 404


def test_rascunho_nunca_aparece(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    with c.local.admin() as con:
        rascunho = con.execute(
            "insert into public.orcamentos (pedido_id, profissional_id, valor_total_centavos) "
            "values (%s, %s, 0) returning id",
            (pedido_id, c.ids["profissional2"]),
        ).fetchone()[0]
    assert get(c, f"/v1/orcamentos/{rascunho}", "cliente").status_code == 404
    assert get(c, f"/v1/orcamentos/{rascunho}", "profissional2").status_code == 404
    assert get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente").json() == []


def test_me_cria_a_linha_se_faltar_e_patch_troca_o_nome(cenario):
    c = cenario
    novo = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (novo,))
    c.ids["novo"] = novo
    # primeiro acesso: o login valida, a linha em `usuarios` nasce (idempotente)
    eu = get(c, "/v1/me", "novo")
    assert eu.status_code == 200, eu.text
    assert eu.json()["papel"] == "cliente" and eu.json()["papeis"] == ["cliente"]
    assert eu.json()["tem_perfil_profissional"] is False and eu.json()["status_verificacao"] is None
    assert get(c, "/v1/me", "novo").json() == eu.json()
    with c.local.admin() as con:
        assert (
            con.execute("select count(*) from public.usuarios where id = %s", (novo,)).fetchone()[0]
            == 1
        )
    r = c.cliente.patch("/v1/me", json={"nome": " Ana   Souza "}, headers=c.token("novo"))
    assert r.status_code == 200 and r.json()["nome"] == "Ana Souza"
    assert get(c, "/v1/me", "novo").json()["nome"] == "Ana Souza"
    for ruim in ({"nome": "a"}, {"nome": "x" * 121}, {"papel": "equipe"}, {}):
        assert c.cliente.patch("/v1/me", json=ruim, headers=c.token("novo")).status_code == 422
    assert (
        c.cliente.patch("/v1/me", json={"nome": "Ana"}, headers=c.token("equipe1")).status_code
        == 403
    )

    # profissional: tem perfil e o status da verificação mais recente
    pro = get(c, "/v1/me", "profissional").json()
    assert pro["papeis"] == ["cliente", "profissional"] and pro["tem_perfil_profissional"] is True
    assert pro["status_verificacao"] is None
    with c.local.admin() as con:
        con.execute(
            "insert into public.verificacoes (profissional_id, nivel_solicitado, "
            "consentimento_lgpd_em) values (%s, 'verificado', now())",
            (c.ids["profissional"],),
        )
    assert get(c, "/v1/me", "profissional").json()["status_verificacao"] == "enviada"
    # nada de dado pessoal
    assert not {"cpf", "telefone", "email"} & set(pro)


def test_pedidos_abertos_filtros_visibilidade_e_recusa(atuacao, com_recusas):
    c = atuacao
    pedido_id = abrir_pedido(c)
    url = "/v1/profissional/pedidos-abertos"
    visto = get(c, url, "profissional").json()
    assert pedido_id in [p["id"] for p in visto]
    # mesma regra da RLS: profissional2 não atua na categoria
    assert pedido_id not in [p["id"] for p in get(c, url, "profissional2").json()]
    # filtros
    por_categoria = get(c, url, "profissional", params={"categoria_id": c.categoria_id}).json()
    assert pedido_id in [p["id"] for p in por_categoria]
    assert get(c, url, "profissional", params={"categoria_id": str(uuid.uuid4())}).json() == []
    assert pedido_id in [
        p["id"] for p in get(c, url, "profissional", params={"bairro": "centro"}).json()
    ]
    assert pedido_id not in [
        p["id"] for p in get(c, url, "profissional", params={"bairro": "Savassi"}).json()
    ]
    assert get(c, url, "profissional", params={"ordenar": "antigos"}).status_code == 200
    assert get(c, url, "profissional", params={"ordenar": "x"}).status_code == 422

    # categoria suspensa some da lista (e a recusa só vale para o que ele podia ver)
    with c.local.admin() as con:
        con.execute(
            "update public.profissional_categorias set suspensa_em = now() "
            "where profissional_id = %s",
            (c.ids["profissional"],),
        )
    assert pedido_id not in [p["id"] for p in get(c, url, "profissional").json()]
    assert (
        post(c, f"/v1/pedidos/{pedido_id}/recusar", "profissional", {"motivo": "x"}).status_code
        == 404
    )
    with c.local.admin() as con:
        con.execute(
            "update public.profissional_categorias set suspensa_em = null "
            "where profissional_id = %s",
            (c.ids["profissional"],),
        )

    # recusar: sai da lista dele, não da do outro, e o pedido continua aberto
    r = post(c, f"/v1/pedidos/{pedido_id}/recusar", "profissional", {"motivo": "Sem agenda"})
    assert r.status_code == 200 and r.json() == {"pedido_id": pedido_id, "recusado": True}
    assert (
        post(
            c, f"/v1/pedidos/{pedido_id}/recusar", "profissional", {"motivo": "Sem agenda"}
        ).status_code
        == 200
    )
    assert pedido_id not in [p["id"] for p in get(c, url, "profissional").json()]
    assert get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["estado"] == "aberto"
    with c.local.admin() as con:
        assert (
            con.execute(
                "select count(*) from public.pedido_recusas where pedido_id = %s", (pedido_id,)
            ).fetchone()[0]
            == 1
        )
    assert (
        post(c, f"/v1/pedidos/{pedido_id}/recusar", "cliente", {"motivo": "x"}).status_code == 403
    )
    assert (
        post(c, f"/v1/pedidos/{pedido_id}/recusar", "profissional", {"motivo": ""}).status_code
        == 422
    )
    assert (
        post(c, f"/v1/pedidos/{uuid.uuid4()}/recusar", "profissional", {"motivo": "x"}).status_code
        == 404
    )


def test_migration_pedido_recusas_aplica_protege_e_desfaz(cenario):
    import psycopg

    c = cenario
    subir = (RAIZ / "supabase/migrations/20261030130000_pedido_recusas.sql").read_text("utf-8")
    descer = (RAIZ / "supabase/rollback/pedido_recusas_rollback.sql").read_text("utf-8")
    pedido_id = abrir_pedido(c)
    with c.local.admin() as con:
        existia = con.execute("select to_regclass('public.pedido_recusas')").fetchone()[0]
        if existia is None:
            con.execute(subir)
        con.execute(
            "insert into public.pedido_recusas (pedido_id, profissional_id, motivo) "
            "values (%s, %s, 'teste')",
            (pedido_id, c.ids["profissional2"]),
        )
        with pytest.raises(psycopg.errors.UniqueViolation):
            con.execute(
                "insert into public.pedido_recusas (pedido_id, profissional_id, motivo) "
                "values (%s, %s, 'de novo')",
                (pedido_id, c.ids["profissional2"]),
            )
        with pytest.raises(psycopg.errors.CheckViolation):
            con.execute(
                "insert into public.pedido_recusas (pedido_id, profissional_id, motivo) "
                "values (%s, %s, '   ')",
                (pedido_id, c.ids["profissional"]),
            )
        with pytest.raises(psycopg.errors.Error):  # recusa não se edita nem se apaga
            con.execute("update public.pedido_recusas set motivo = 'x'")
        with pytest.raises(psycopg.errors.Error):
            con.execute("delete from public.pedido_recusas")
        if existia is None:  # só desfaz se esta chamada foi quem aplicou
            con.execute(descer)
            assert con.execute("select to_regclass('public.pedido_recusas')").fetchone()[0] is None


# --- contrato em andamento: garantia, aditivos, notas -------------------------------------


def _em_andamento(c) -> str:
    pedido_id = abrir_pedido(c)
    orcamento_id = enviar_orcamento(c, pedido_id)
    assert (
        acao(
            c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id}
        ).status_code
        == 200
    )
    t = estados.transicionar(
        c.contexto.pedidos.obter(pedido_id),
        estados.Acao.CONFIRMAR_PAGAMENTO,
        Ator(Papel.SISTEMA, "sistema"),
        agora(),
        ProvaPagamento(f"pi_{uuid.uuid4().hex[:8]}"),
    )
    c.contexto.pedidos.salvar(t.pedido, t.evento)
    inicio = agora() + timedelta(days=2)
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    assert (
        acao(c, "profissional", pedido_id, "confirmar_agenda", {"janela": janela}).status_code
        == 200
    )
    codigo = get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["codigo_inicio"]
    entrada = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": codigo,
    }
    assert acao(c, "profissional", pedido_id, "fazer_check_in", entrada).status_code == 200
    return pedido_id


def test_garantia_aditivo_e_nota_de_material(cenario):
    c = cenario
    pedido_id = _em_andamento(c)

    g = get(c, f"/v1/contratos/{pedido_id}/garantia", "cliente").json()
    assert g["iniciada"] is False and g["ativa"] is False

    # aditivo: o profissional propõe, só o cliente decide
    base = f"/v1/contratos/{pedido_id}/aditivos"
    assert post(c, base, "cliente", {"descricao": "x", "valor_centavos": 100}).status_code == 403
    r = post(c, base, "profissional", {"descricao": "Trocar registro", "valor_centavos": 15_000})
    assert r.status_code == 201, r.text
    aid = r.json()["id"]
    assert r.json()["estado"] == "proposto"
    assert post(c, f"{base}/{aid}/aprovar", "profissional").status_code == 403
    assert post(c, f"{base}/{aid}/aprovar", "cliente2").status_code == 404
    ok = post(c, f"{base}/{aid}/aprovar", "cliente")
    assert ok.status_code == 200, ok.text
    assert ok.json()["aditivo"]["estado"] == "aprovado" and ok.json()["cobranca"] is None
    assert post(c, f"{base}/{aid}/recusar", "cliente").status_code == 409  # decidido não muda
    outro = post(c, base, "profissional", {"descricao": "Extra", "valor_centavos": 500}).json()[
        "id"
    ]
    rec = post(c, f"{base}/{outro}/recusar", "cliente")
    assert rec.status_code == 200 and rec.json()["aditivo"]["estado"] == "recusado"
    lista = get(c, base, "cliente").json()
    assert [(a["id"], a["estado"]) for a in lista] == [(aid, "aprovado"), (outro, "recusado")]
    assert get(c, base, "profissional2").status_code == 404

    # nota de material: foto + itens; total conferido pelo banco
    url = f"/v1/contratos/{pedido_id}/notas-material"
    corpo = {
        "foto_storage_path": f"{pedido_id}/nota-{uuid.uuid4().hex}.jpg",
        "itens": [
            {"descricao": "Cano", "quantidade": "2.5", "valor_unitario_centavos": 1_001},
            {"descricao": "Cola", "quantidade": 1, "valor_unitario_centavos": 1_500},
        ],
    }
    r = post(c, url, "profissional", corpo)
    assert r.status_code == 201, r.text
    assert r.json()["total_centavos"] == 4_003 and r.json()["itens"][0]["total_centavos"] == 2_503
    assert post(c, url, "cliente", corpo).status_code == 403
    assert post(c, url, "profissional2", corpo).status_code == 404
    lista = get(c, url, "cliente").json()
    assert len(lista) == 1 and lista[0]["id"] == r.json()["id"]
    assert lista[0]["itens"][1]["descricao"] == "Cola"
    assert get(c, url, "cliente2").status_code == 404

    # garantia nasce na conclusão; avaliação pelo contrato
    codigo = get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["codigo_conclusao"]
    out = acao(c, "profissional", pedido_id, "fazer_check_out",
               {"foto_final": foto("fim"), "codigo_conclusao": codigo})  # fmt: skip
    assert out.status_code == 200, out.text
    assert acao(c, "cliente", pedido_id, "confirmar_conclusao").status_code == 200
    g = get(c, f"/v1/contratos/{pedido_id}/garantia", "cliente").json()
    assert g["iniciada"] and g["ativa"] and g["dias"] == 90  # garantia da categoria do cenário
    av = post(c, f"/v1/contratos/{pedido_id}/avaliacao", "cliente", {"nota_geral": 5})
    assert av.status_code == 201 and av.json()["direcao"] == "cliente_para_profissional"
    assert (
        post(c, f"/v1/contratos/{pedido_id}/avaliacao", "cliente", {"nota_geral": 5}).status_code
        == 409
    )
