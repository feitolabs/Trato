"""Rotas do app contra o Postgres local descartável: pedido de Aberto a Concluído e, no caminho,
orçamentos, valores do pagamento, mensagens, notificações, perfil, pedidos abertos, resumo,
verificação e avaliação. Nunca toca no Supabase real."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.pedidos import estados
from trato.pedidos.estados import Ator, Papel, ProvaPagamento

from .test_fluxo_postgres import abrir_pedido, acao, enviar_orcamento, foto

pytestmark = pytest.mark.integracao


def agora() -> datetime:
    return datetime.now(UTC)


def get(c, url, quem, **kw):
    return c.cliente.get(url, headers=c.token(quem), **kw)


def post(c, url, quem, corpo=None, **kw):
    return c.cliente.post(url, json=corpo, headers=c.token(quem), **kw)


@pytest.fixture
def atuacao(cenario):
    """O profissional 'profissional' atua na categoria e na cidade do cenário; o outro, não."""
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


def test_pedido_de_aberto_a_concluido_com_as_rotas_do_app(atuacao):
    c = atuacao
    pedido_id = abrir_pedido(c)

    # pedidos abertos: aparece para quem atua na categoria/cidade, não para o outro; sem endereço
    abertos = get(c, "/v1/profissional/pedidos-abertos", "profissional").json()
    achado = next(p for p in abertos if p["id"] == pedido_id)
    assert achado["titulo"] == "Pintar a sala" and achado["bairro"] == "Centro"
    assert "Rua A" not in str(achado)
    assert pedido_id not in [
        p["id"] for p in get(c, "/v1/profissional/pedidos-abertos", "profissional2").json()
    ]
    assert get(c, "/v1/profissional/pedidos-abertos", "cliente").status_code == 403

    # resumo: a taxa vem da faixa vigente do banco (750 bps para 90.000), nunca do app
    r = post(c, "/v1/orcamentos/resumo", "profissional", {"valor_centavos": 90_000})
    assert r.json() == {
        "valor_centavos": 90_000,
        "taxa_centavos": 6_750,
        "liquido_centavos": 83_250,
    }
    r = post(c, "/v1/orcamentos/resumo", "profissional", {"valor_centavos": 200_000})
    assert r.json()["taxa_centavos"] == 12_000  # faixa de 600 bps acima de 100.000

    # sem orçamento ainda
    assert get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente").json() == []

    # mensagem antes da contratação: contato oculto; só o texto exibido sai pela API
    url_msg = f"/v1/pedidos/{pedido_id}/mensagens"
    r = post(c, url_msg, "profissional", {"texto": "Posso ir amanhã. Zap 31 99999-8888"})
    assert r.status_code == 201, r.text
    assert r.json()["mascarada"] is True and "99999" not in r.json()["texto"]
    assert (
        get(c, url_msg, "cliente").status_code == 422
    )  # ninguém contratado: escolha o profissional
    assert (
        get(c, url_msg, "cliente", params={"profissional_id": c.ids["profissional"]}).status_code
        == 404
    )  # noqa: E501 - ainda não orçou

    # orçamento do profissional; o cliente vê (do mais barato ao mais caro) e conversa
    orcamento_id = enviar_orcamento(c, pedido_id)
    enviar_orcamento(c, pedido_id, "profissional2")
    lista = get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente").json()
    assert len(lista) == 2 and {o["profissional_nome"] for o in lista} == {
        "profissional",
        "profissional2",
    }
    assert [o["valor_centavos"] for o in lista] == [90_000, 90_000]
    assert not any(o["aceito"] for o in lista)
    meu = get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional").json()
    assert [o["id"] for o in meu] == [orcamento_id]  # cada um vê só o seu
    r = post(
        c,
        url_msg,
        "cliente",
        {"texto": "Combinado!"},
        params={"profissional_id": c.ids["profissional"]},
    )
    assert r.status_code == 201 and r.json()["minha"] is True
    historia = get(c, url_msg, "profissional").json()
    assert [m["minha"] for m in historia] == [True, False]
    assert get(c, url_msg, "profissional2").json() == []  # conversas separadas
    assert get(c, url_msg, "cliente2").status_code == 404

    # aceite: o orçamento aceito vem marcado; valores do pagamento vêm do contrato
    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id})
    assert r.status_code == 200, r.text
    lista = get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente").json()
    assert [o["aceito"] for o in lista if o["id"] == orcamento_id] == [True]
    valores = get(c, f"/v1/pedidos/{pedido_id}/pagamento", "cliente").json()
    assert valores["valor_centavos"] == 90_000 and valores["pagamento_confirmado"] is False
    assert valores["pago_centavos"] == 0 and valores["meios_disponiveis"] == ["pix", "cartao"]
    assert get(c, f"/v1/pedidos/{pedido_id}/pagamento", "profissional").status_code == 403

    # depois da contratação o contato deixa de ser mascarado
    r = post(c, url_msg, "profissional", {"texto": "Meu zap 31 99999-8888"})
    assert r.json()["mascarada"] is False and "99999" in r.json()["texto"]

    # pagamento só por webhook assinado (simulado: ator sistema, como no fluxo existente)
    pedido = c.contexto.pedidos.obter(pedido_id)
    t = estados.transicionar(
        pedido,
        estados.Acao.CONFIRMAR_PAGAMENTO,
        Ator(Papel.SISTEMA, "sistema"),
        agora(),
        ProvaPagamento("pi_teste_app"),
    )
    c.contexto.pedidos.salvar(t.pedido, t.evento)
    assert get(c, f"/v1/pedidos/{pedido_id}/pagamento", "cliente").json()["pagamento_confirmado"]

    # agenda, check-in e check-out
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
    codigo_saida = get(c, f"/v1/pedidos/{pedido_id}", "cliente").json()["codigo_conclusao"]
    r = acao(c, "profissional", pedido_id, "fazer_check_out",
             {"foto_final": foto("fim"), "codigo_conclusao": codigo_saida})  # fmt: skip
    assert r.json()["estado"] == "em_confirmacao"

    # avaliar antes de concluir não vale; depois, cada lado avalia uma vez
    url_av = f"/v1/pedidos/{pedido_id}/avaliacao"
    assert post(c, url_av, "cliente", {"nota_geral": 5}).status_code == 409
    assert acao(c, "cliente", pedido_id, "confirmar_conclusao").json()["estado"] == "concluido"
    r = post(
        c, url_av, "cliente", {"nota_geral": 5, "comentario": "Excelente", "etiquetas": ["pontual"]}
    )
    assert r.status_code == 201 and r.json()["direcao"] == "cliente_para_profissional"
    assert post(c, url_av, "cliente", {"nota_geral": 4}).status_code == 409
    assert post(c, url_av, "profissional", {"nota_geral": 5}).status_code == 201
    assert post(c, url_av, "cliente2", {"nota_geral": 5}).status_code == 404
    assert post(c, url_av, "equipe1", {"nota_geral": 5}).status_code == 403

    # notificações do usuário (a criação é do sistema; a rota só lê)
    assert get(c, "/v1/notificacoes", "cliente2").json() == []
    c.contexto.notificacoes.criar(
        c.ids["cliente"], "pedido.concluido", "Serviço concluído", dados={"pedido_id": pedido_id}
    )
    notas = get(c, "/v1/notificacoes", "cliente").json()
    assert notas[0]["titulo"] == "Serviço concluído" and notas[0]["lida"] is False
    assert notas[0]["dados"] == {"pedido_id": pedido_id}
    assert get(c, "/v1/notificacoes", "cliente2").json() == []  # não vaza para outra pessoa


def test_me_do_cliente_e_do_profissional(cenario):
    c = cenario
    eu = get(c, "/v1/me", "cliente").json()
    assert eu["id"] == c.ids["cliente"] and eu["papel"] == "cliente" and eu["nome"] == "cliente"
    assert eu["nivel_verificacao"] is None
    pro = get(c, "/v1/me", "profissional").json()
    assert pro["papel"] == "profissional" and pro["nivel_verificacao"] == "verificado"
    assert pro["servicos_concluidos"] == 0
    assert c.cliente.get("/v1/me").status_code == 401
    # nada de dado pessoal na resposta
    assert set(pro) == {
        "id", "nome", "papel", "status", "nivel_verificacao", "nota_publica", "servicos_concluidos"
    }  # fmt: skip


def test_verificacao_do_profissional_no_banco(cenario):
    c = cenario
    novo = str(uuid.uuid4())
    c.ids["novo"] = novo
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (novo,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'novo')", (novo,))
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (novo,))
    url = "/v1/profissional/verificacao"
    corpo = {
        "consentimento_lgpd": True,
        "documentos": [
            {"tipo": "documento_frente", "storage_path": f"{novo}/pendente/frente.jpg"},
            {"tipo": "selfie", "storage_path": f"verificacao/{novo}/pendente/selfie.jpg"},
        ],
    }
    # perfil ainda em análise: o login o trata como cliente, e é ele quem pode se verificar
    assert get(c, "/v1/me", "novo").json()["papel"] == "cliente"
    assert post(c, url, "novo", {**corpo, "consentimento_lgpd": False}).status_code == 422
    r = post(c, url, "novo", corpo)
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "enviada" and r.json()["documentos"] == [
        "documento_frente",
        "selfie",
    ]
    with c.local.admin() as con:
        linhas = con.execute(
            "select d.tipo, d.storage_path, v.status, v.consentimento_lgpd_em is not null "
            "from public.verificacao_documentos d "
            "join public.verificacoes v on v.id = d.verificacao_id "
            "where v.profissional_id = %s order by d.tipo",
            (novo,),
        ).fetchall()
    assert [(tipo, status, lgpd) for tipo, _, status, lgpd in linhas] == [
        ("documento_frente", "enviada", True),
        ("selfie", "enviada", True),
    ]
    assert get(c, url, "novo").json()[0]["id"] == r.json()["id"]
    assert post(c, url, "novo", corpo).status_code == 409  # já tem uma em análise
    # quem não tem cadastro de profissional recebe um aviso claro, e o caminho do outro não vale
    r = post(c, url, "cliente", {**corpo, "documentos": [
        {"tipo": "documento_frente", "storage_path": f"{c.ids['cliente']}/p/f.jpg"},
        {"tipo": "selfie", "storage_path": f"{c.ids['cliente']}/p/s.jpg"},
    ]})  # fmt: skip
    assert r.status_code == 404 and "cadastro de profissional" in r.json()["detail"]
    assert post(c, url, "profissional", corpo).status_code == 422  # caminhos são de outra pessoa
    assert post(c, url, "equipe1", corpo).status_code == 403
