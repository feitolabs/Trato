"""Rotas que o app pede (memória): orçamentos, pagamento, mensagens, notificações, perfil,
pedidos abertos, resumo de orçamento, verificação e avaliação."""

from __future__ import annotations

from conftest import AGORA, CLIENTE, OUTRO_CLIENTE, PROFISSIONAL, cab

from trato.api.auth import PapelUsuario
from trato.api.memoria_app import TaxaEmMemoria
from trato.api.repositorios import DadosPedido, Orcamento
from trato.api.repositorios_app import PerfilDetalhe
from trato.pagamentos.taxa import ConfigTaxa
from trato.pedidos.estados import Estado


def get(amb, url, quem="t-cliente", **kw):
    return amb.cliente.get(url, headers=cab(quem), **kw)


def post(amb, url, token, corpo=None, **kw):
    return amb.cliente.post(url, json=corpo, headers=cab(token), **kw)


# --- orçamentos do pedido ---------------------------------------------------------------


def test_cliente_ve_orcamentos_do_pedido_do_mais_barato_ao_mais_caro(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.orcamentos.adicionar(Orcamento("orc-2", "ped-1", "pro-2", 80_000))
    r = get(amb, "/v1/pedidos/ped-1/orcamentos")
    assert r.status_code == 200
    assert [o["valor_centavos"] for o in r.json()] == [80_000, 100_000]
    assert not any(o["aceito"] for o in r.json())


def test_orcamento_aceito_vem_marcado(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    r = get(amb, "/v1/pedidos/ped-1/orcamentos")
    assert [(o["id"], o["aceito"]) for o in r.json()] == [("orc-1", True)]


def test_profissional_so_ve_o_proprio_orcamento(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.orcamentos.adicionar(Orcamento("orc-2", "ped-1", "pro-2", 80_000))
    r = get(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof")
    assert [o["id"] for o in r.json()] == ["orc-1"]


def test_orcamentos_de_pedido_alheio_dao_404(amb):
    amb.semear_pedido(Estado.ABERTO)
    assert get(amb, "/v1/pedidos/ped-1/orcamentos", "t-outro-cliente").status_code == 404
    assert get(amb, "/v1/pedidos/nao-existe/orcamentos").status_code == 404
    assert get(amb, "/v1/pedidos/ped-1/orcamentos", "ruim").status_code == 401


# --- valores do pagamento ---------------------------------------------------------------


def test_valores_do_pagamento_antes_e_depois_de_pagar(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    r = get(amb, "/v1/pedidos/ped-1/pagamento")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["valor_centavos"] == 100_000
    assert corpo["pago_centavos"] == 0 and corpo["pagamento_confirmado"] is False
    assert corpo["meios_disponiveis"] == ["pix", "cartao"]
    assert "taxa_centavos" not in corpo  # a taxa é do profissional, não aparece para o cliente

    amb.semear_dinheiro()
    assert get(amb, "/v1/pedidos/ped-1/pagamento").json()["pago_centavos"] == 100_000


def test_valores_do_pagamento_so_do_cliente_dono(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    assert get(amb, "/v1/pedidos/ped-1/pagamento", "t-prof").status_code == 403
    assert get(amb, "/v1/pedidos/ped-1/pagamento", "t-outro-cliente").status_code == 404


# --- resumo (taxa só no backend) --------------------------------------------------------


def test_resumo_calcula_taxa_e_liquido_no_backend(amb):
    amb.contexto.taxa = TaxaEmMemoria(ConfigTaxa(750, 500))
    r = post(amb, "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 100_000})
    assert r.status_code == 200
    corpo = r.json()
    assert {k: corpo[k] for k in ("valor_centavos", "taxa_centavos", "liquido_centavos")} == {
        "valor_centavos": 100_000,
        "taxa_centavos": 7_500,
        "liquido_centavos": 92_500,
    }
    assert corpo["custo_provedor_estimado_centavos"] > 0
    # abaixo do mínimo cobra o mínimo; nunca mais que o valor
    r = post(amb, "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 1_000})
    assert r.json()["taxa_centavos"] == 500 and r.json()["liquido_centavos"] == 500


def test_resumo_recusa_valor_ruim_papel_errado_e_taxa_nao_configurada(amb):
    assert (
        post(amb, "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 5_000}).status_code == 503
    )
    amb.contexto.taxa = TaxaEmMemoria(ConfigTaxa(750, 500))
    for valor in (0, -1, 1.5, "10"):
        r = post(amb, "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": valor})
        assert r.status_code == 422, valor
    assert (
        post(amb, "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 100, "taxa": 1}).status_code
        == 422
    )
    assert (
        post(amb, "/v1/orcamentos/resumo", "t-cliente", {"valor_centavos": 5_000}).status_code
        == 403
    )


# --- mensagens --------------------------------------------------------------------------


def test_mensagens_antes_da_contratacao_mascaram_contato(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.contratos._itens.clear()  # ainda sem contrato
    url = "/v1/pedidos/ped-1/mensagens"
    # o profissional fala em pedido aberto; o cliente escolhe com quem
    r = post(amb, url, "t-prof", {"texto": "Meu zap 31 99999-8888 ou a@b.com"})
    assert r.status_code == 201
    assert r.json()["mascarada"] is True and "99999" not in r.json()["texto"]
    assert r.json()["minha"] is True
    assert get(amb, url).status_code == 422  # cliente sem dizer o profissional
    lista = get(amb, url, params={"profissional_id": PROFISSIONAL.id}).json()
    assert len(lista) == 1 and lista[0]["minha"] is False
    r = post(
        amb,
        url,
        "t-cliente",
        {"texto": "Pode vir amanhã?"},
        params={"profissional_id": PROFISSIONAL.id},
    )
    assert r.status_code == 201
    assert [m["autor_id"] for m in get(amb, url, "t-prof").json()] == [PROFISSIONAL.id, CLIENTE.id]


def test_mensagens_depois_do_contrato_nao_mascaram(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    url = "/v1/pedidos/ped-1/mensagens"
    r = post(amb, url, "t-cliente", {"texto": "Meu zap 31 99999-8888"})
    assert r.status_code == 201 and r.json()["mascarada"] is False
    assert "99999" in get(amb, url, "t-prof").json()[0]["texto"]


def test_mensagens_acesso_e_validacao(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    url = "/v1/pedidos/ped-1/mensagens"
    assert get(amb, url, "t-outro-cliente").status_code == 404
    assert get(amb, url, "t-outro-prof").status_code == 404  # pedido já contratado com outro
    assert post(amb, url, "t-outro-prof", {"texto": "oi"}).status_code == 404
    assert post(amb, url, "t-equipe", {"texto": "oi"}).status_code == 403
    assert post(amb, url, "t-cliente", {"texto": ""}).status_code == 422
    assert post(amb, url, "t-cliente", {"texto": "x" * 2001}).status_code == 422
    # cliente não conversa com quem não orçou nem foi contratado
    r = get(amb, url, params={"profissional_id": "pro-2"})
    assert r.status_code == 404


# --- notificações e perfil --------------------------------------------------------------


def test_notificacoes_do_usuario(amb):
    assert get(amb, "/v1/notificacoes").json() == []
    amb.contexto.notificacoes.criar(CLIENTE.id, "orcamento.novo", "Novo orçamento", dados={"p": 1})
    amb.contexto.notificacoes.criar(OUTRO_CLIENTE.id, "x", "De outra pessoa")
    r = get(amb, "/v1/notificacoes")
    assert [n["titulo"] for n in r.json()] == ["Novo orçamento"]
    assert r.json()[0]["lida"] is False and r.json()[0]["dados"] == {"p": 1}
    assert get(amb, "/v1/notificacoes", "t-equipe").status_code == 403
    assert amb.cliente.get("/v1/notificacoes").status_code == 401


def test_me_devolve_o_perfil_sem_dados_pessoais(amb):
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe("pro-1", "Ana", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 4.8, 12)
    )
    r = get(amb, "/v1/me", "t-prof")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo.pop("papeis") == ["cliente", "profissional"]
    assert corpo.pop("tem_perfil_profissional") is True
    assert corpo.pop("status_verificacao") is None
    assert corpo == {
        "id": "pro-1", "nome": "Ana", "papel": "profissional", "status": "ativo",
        "nivel_verificacao": "verificado", "nota_publica": 4.8, "servicos_concluidos": 12,
    }  # fmt: skip
    # usuário sem cadastro detalhado ainda responde com o que o login diz
    assert get(amb, "/v1/me").json()["papel"] == "cliente"
    assert amb.cliente.get("/v1/me").status_code == 401


# --- pedidos abertos --------------------------------------------------------------------


def test_pedidos_abertos_do_profissional(amb):
    abrir = post(amb, "/v1/pedidos", "t-cliente")
    assert abrir.status_code == 201
    amb.semear_pedido(Estado.PAGO_E_RETIDO, id="ped-fechado")
    amb.contexto.pedidos.salvar(
        amb.contexto.pedidos.obter(abrir.json()["id"]),
        None,
        DadosPedido("cat", "cid", "Pintar a sala", "Duas demãos", bairro="Centro", urgente=True),
    )
    r = get(amb, "/v1/profissional/pedidos-abertos", "t-prof")
    assert r.status_code == 200
    assert [p["id"] for p in r.json()] == [abrir.json()["id"]]
    assert r.json()[0]["titulo"] == "Pintar a sala" and r.json()[0]["urgente"] is True
    assert "endereco" not in r.json()[0]
    assert get(amb, "/v1/profissional/pedidos-abertos", "t-cliente").status_code == 403


# --- verificação do profissional --------------------------------------------------------


def verificacao(**extra):
    base = {
        "consentimento_lgpd": True,
        "documentos": [
            {"tipo": "documento_frente", "storage_path": "pro-1/ver-a/frente.jpg"},
            {"tipo": "selfie", "storage_path": "verificacao/pro-1/ver-a/selfie.jpg"},
        ],
    }
    return {**base, **extra}


def test_envio_da_verificacao_guarda_so_referencias(amb):
    r = post(amb, "/v1/profissional/verificacao", "t-prof", verificacao())
    assert r.status_code == 201, r.text
    assert r.json()["status"] == "enviada" and r.json()["documentos"] == [
        "documento_frente",
        "selfie",
    ]
    assert "frente.jpg" not in r.text  # caminho dos arquivos não volta ao app
    lista = get(amb, "/v1/profissional/verificacao", "t-prof").json()
    assert [v["id"] for v in lista] == [r.json()["id"]]
    assert get(amb, "/v1/profissional/verificacao", "t-outro-prof").json() == []


def test_verificacao_recusa_envio_incompleto_ou_perigoso(amb):
    url = "/v1/profissional/verificacao"
    assert post(amb, url, "t-prof", verificacao(consentimento_lgpd=False)).status_code == 422
    assert post(amb, url, "t-prof", verificacao(nivel_solicitado="vip")).status_code == 422
    assert post(amb, url, "t-prof", verificacao(documentos=[])).status_code == 422
    so_selfie = [{"tipo": "selfie", "storage_path": "pro-1/v/s.jpg"}]
    assert post(amb, url, "t-prof", verificacao(documentos=so_selfie)).status_code == 422
    tipo_ruim = [*verificacao()["documentos"], {"tipo": "cpf", "storage_path": "pro-1/v/c.jpg"}]
    assert post(amb, url, "t-prof", verificacao(documentos=tipo_ruim)).status_code == 422
    for caminho in (
        "https://x.com/a.jpg",
        "pro-1/../pro-2/a.jpg",
        "pro-2/v/a.jpg",
        "/pro-1/v/a.jpg",
    ):
        docs = [
            {"tipo": "documento_frente", "storage_path": caminho},
            {"tipo": "selfie", "storage_path": "pro-1/v/s.jpg"},
        ]
        assert post(amb, url, "t-prof", verificacao(documentos=docs)).status_code == 422, caminho
    assert post(amb, url, "t-equipe", verificacao()).status_code == 403
    assert amb.cliente.post(url, json=verificacao()).status_code == 401


# --- avaliação --------------------------------------------------------------------------


def test_cliente_e_profissional_avaliam_uma_vez_cada(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    url = "/v1/pedidos/ped-1/avaliacao"
    r = post(
        amb, url, "t-cliente", {"nota_geral": 5, "comentario": " Ótimo ", "etiquetas": ["pontual"]}
    )
    assert r.status_code == 201, r.text
    assert r.json()["direcao"] == "cliente_para_profissional"
    assert r.json()["comentario"] == "Ótimo" and r.json()["etiquetas"] == ["pontual"]
    assert post(amb, url, "t-cliente", {"nota_geral": 1}).status_code == 409  # só uma vez
    r = post(amb, url, "t-prof", {"nota_geral": 4})
    assert r.status_code == 201 and r.json()["direcao"] == "profissional_para_cliente"
    salva = amb.contexto.avaliacoes.obter("ped-1", "cliente_para_profissional")
    assert salva.avaliador_id == CLIENTE.id and salva.avaliado_id == PROFISSIONAL.id


def test_avaliacao_recusa_antes_da_conclusao_nota_ruim_e_estranhos(amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    url = "/v1/pedidos/ped-1/avaliacao"
    assert post(amb, url, "t-cliente", {"nota_geral": 5}).status_code == 409
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    for nota in (0, 6, 3.5, "5"):
        assert post(amb, url, "t-cliente", {"nota_geral": nota}).status_code == 422, nota
    assert post(amb, url, "t-cliente", {"nota_geral": 5, "x": 1}).status_code == 422
    assert post(amb, url, "t-outro-cliente", {"nota_geral": 5}).status_code == 404
    assert post(amb, url, "t-outro-prof", {"nota_geral": 5}).status_code == 404
    assert post(amb, url, "t-equipe", {"nota_geral": 5}).status_code == 403
    assert amb.cliente.post(url, json={"nota_geral": 5}).status_code == 401
