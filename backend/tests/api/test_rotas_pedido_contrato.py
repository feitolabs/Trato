# ruff: noqa: F811  (a fixture `fluxo` vem importada de test_fluxo_pagamento_e2e)
"""Rotas em volta do orçamento e do contrato (memória): detalhe do orçamento, cobrança e estado do
pagamento, garantia, aditivos, nota de material, avaliação, perfil e pedidos abertos."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401, F811  (fixture)

from trato.api.repositorios_app import PerfilDetalhe
from trato.pagamentos.provedor import TipoEvento
from trato.pagamentos.taxa import ConfigTaxa
from trato.pedidos.estados import Estado


def chamar(amb, metodo, url, quem, corpo=None, **kw):
    return amb.cliente.request(metodo, url, json=corpo, headers=cab(quem), **kw)


# --- orçamento ---------------------------------------------------------------------------


def test_detalhe_do_orcamento_so_para_cliente_dono_e_autor(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    r = chamar(amb, "GET", "/v1/orcamentos/orc-1", "t-cliente")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["valor_centavos"] == 100_000 and corpo["itens"] == []
    assert {"validade_ate", "fora_do_escopo", "aceito"} <= set(corpo)
    assert chamar(amb, "GET", "/v1/orcamentos/orc-1", "t-prof").status_code == 200
    assert chamar(amb, "GET", "/v1/orcamentos/orc-1", "t-outro-cliente").status_code == 404
    assert chamar(amb, "GET", "/v1/orcamentos/orc-1", "t-outro-prof").status_code == 404
    assert chamar(amb, "GET", "/v1/orcamentos/orc-1", "t-equipe").status_code == 403
    assert chamar(amb, "GET", "/v1/orcamentos/nao-existe", "t-cliente").status_code == 404
    assert amb.cliente.get("/v1/orcamentos/orc-1").status_code == 401


def test_resumo_traz_taxa_liquido_e_custo_estimado_do_provedor(amb):
    from trato.api.memoria_app import TaxaEmMemoria

    amb.contexto.taxa = TaxaEmMemoria(ConfigTaxa(750, 500))
    r = chamar(amb, "POST", "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 100_000})
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["taxa_centavos"] == 7_500 and corpo["liquido_centavos"] == 92_500
    assert corpo["custo_provedor_estimado_centavos"] > 0
    assert corpo["custo_provedor_estimativa"] is True
    assert (
        chamar(amb, "POST", "/v1/orcamentos/resumo", "t-cliente", {"valor_centavos": 1}).status_code
        == 403
    )
    assert (
        chamar(amb, "POST", "/v1/orcamentos/resumo", "t-prof", {"valor_centavos": 1.5}).status_code
        == 422
    )


# --- cobrança e estado do pagamento -------------------------------------------------------


def test_cobranca_nunca_devolve_pago_antes_do_webhook(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    antes = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert antes["estado_pagamento"] == "sem_cobranca" and antes["pago"] is False

    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix"})
    assert r.status_code == 201, r.text
    cobranca = r.json()
    assert cobranca["estado_pagamento"] == "aguardando_confirmacao"
    assert cobranca["tipo_instrucao"] == "pix_copia_e_cola" and cobranca["instrucao"]
    assert cobranca["valor_centavos"] == 100_000

    # repetir devolve a mesma cobrança pendente (idempotente)
    outra = fluxo.chamar(
        "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix"}
    ).json()
    assert outra["cobranca_id"] == cobranca["cobranca_id"]

    # o provedor marcar como paga NÃO basta: só o webhook assinado
    fluxo.fake.marcar_paga(cobranca["cobranca_id"])
    meio = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()
    assert meio["estado_pagamento"] == "aguardando_confirmacao" and meio["pago"] is False
    assert meio["pago_centavos"] == 0

    # webhook sem assinatura é recusado e nada muda
    ruim = fluxo.http.post("/v1/webhooks/stripe", content=b"{}", headers={"Stripe-Signature": "x"})
    assert ruim.status_code >= 400
    assert (
        fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-cliente").json()["pago"] is False
    )

    assert (
        fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["cobranca_id"]).status_code == 200
    )
    depois = fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-prof").json()
    assert depois["estado_pagamento"] == "pago" and depois["pago"] is True
    assert depois["pago_centavos"] == 100_000
    # pago: não cobra de novo
    assert (
        fluxo.chamar(
            "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "pix"}
        ).status_code
        == 409
    )


def test_cobranca_so_do_cliente_do_contrato(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    corpo = {"meio": "cartao"}
    assert fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-prof", corpo).status_code == 403
    assert (
        fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-outro-cliente", corpo).status_code
        == 404
    )
    assert (
        fluxo.chamar(
            "POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", {"meio": "boleto"}
        ).status_code
        == 422
    )
    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", corpo)
    assert r.status_code == 201 and r.json()["tipo_instrucao"] == "cartao_segredo_do_cliente"
    assert fluxo.chamar("GET", f"/v1/contratos/{pid}/pagamento", "t-outro-prof").status_code == 404
    # pedido que não espera pagamento
    fluxo.amb.contexto.pedidos.salvar(
        replace(fluxo.amb.contexto.pedidos.obter(pid), estado=Estado.EM_ANDAMENTO)
    )
    assert (
        fluxo.chamar("POST", f"/v1/contratos/{pid}/cobranca", "t-cliente", corpo).status_code == 409
    )


def test_cobranca_sem_servico_de_pagamento_responde_503(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    r = chamar(amb, "POST", "/v1/contratos/ped-1/cobranca", "t-cliente", {"meio": "pix"})
    assert r.status_code == 503


# --- garantia ----------------------------------------------------------------------------


def test_garantia_antes_e_depois_da_conclusao(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    antes = fluxo.chamar("GET", f"/v1/contratos/{pid}/garantia", "t-cliente").json()
    assert antes["iniciada"] is False and antes["ativa"] is False
    fluxo.concluir(pid)
    g = fluxo.chamar("GET", f"/v1/contratos/{pid}/garantia", "t-cliente").json()
    assert g["iniciada"] and g["ativa"] and g["dias"] == 30  # ConfigGarantia do teste
    assert fluxo.chamar("GET", f"/v1/contratos/{pid}/garantia", "t-prof").status_code == 200
    assert (
        fluxo.chamar("GET", f"/v1/contratos/{pid}/garantia", "t-outro-cliente").status_code == 404
    )
    fluxo.amb.relogio.avancar(days=31)
    assert (
        fluxo.chamar("GET", f"/v1/contratos/{pid}/garantia", "t-cliente").json()["ativa"] is False
    )


# --- aditivos ----------------------------------------------------------------------------


def _em_andamento(fluxo: Fluxo) -> str:
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    assert fluxo.pedido(pid)["estado"] == "em_andamento"
    return pid


def test_aditivo_proposto_pelo_profissional_e_aprovado_so_pelo_cliente(fluxo: Fluxo):  # noqa: F811
    pid = _em_andamento(fluxo)
    base = f"/v1/contratos/{pid}/aditivos"
    assert (
        fluxo.chamar(
            "POST", base, "t-cliente", {"descricao": "x", "valor_centavos": 10}
        ).status_code
        == 403
    )
    r = fluxo.chamar(
        "POST", base, "t-prof", {"descricao": "Trocar o registro", "valor_centavos": 20_000}
    )
    assert r.status_code == 201 and r.json()["estado"] == "proposto"
    aid = r.json()["id"]
    assert (
        fluxo.chamar("POST", base, "t-prof", {"descricao": "x", "valor_centavos": 0}).status_code
        == 422
    )
    assert (
        fluxo.chamar("POST", base, "t-prof", {"descricao": "x", "valor_centavos": 1.5}).status_code
        == 422
    )

    # o profissional não aprova o próprio aditivo
    assert fluxo.chamar("POST", f"{base}/{aid}/aprovar", "t-prof").status_code == 403
    assert fluxo.chamar("POST", f"{base}/{aid}/aprovar", "t-outro-cliente").status_code == 404
    ok = fluxo.chamar("POST", f"{base}/{aid}/aprovar", "t-cliente", {"meio": "pix"})
    assert ok.status_code == 200, ok.text
    corpo = ok.json()
    assert corpo["aditivo"]["estado"] == "aprovado"
    assert corpo["cobranca"]["estado_pagamento"] == "aguardando_confirmacao"
    # decidido não muda mais
    assert fluxo.chamar("POST", f"{base}/{aid}/recusar", "t-cliente").status_code == 409
    lista = fluxo.chamar("GET", base, "t-prof").json()
    assert [(a["id"], a["estado"]) for a in lista] == [(aid, "aprovado")]


def test_aditivo_recusado_nao_gera_cobranca(fluxo: Fluxo):  # noqa: F811
    pid = _em_andamento(fluxo)
    base = f"/v1/contratos/{pid}/aditivos"
    aid = fluxo.chamar(
        "POST", base, "t-prof", {"descricao": "Extra", "valor_centavos": 5_000}
    ).json()["id"]
    r = fluxo.chamar("POST", f"{base}/{aid}/recusar", "t-cliente")
    assert r.status_code == 200 and r.json()["aditivo"]["estado"] == "recusado"
    assert r.json()["cobranca"] is None
    assert fluxo.chamar("POST", f"{base}/{aid}/aprovar", "t-cliente").status_code == 409
    assert fluxo.chamar("POST", f"{base}/nao-existe/recusar", "t-cliente").status_code == 404
    assert fluxo.servico.cobrancas.do_pedido(pid)[-1].aditivo_id is None  # só a principal


def test_aditivo_fora_do_andamento_e_texto_com_contato(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    base = f"/v1/contratos/{pid}/aditivos"
    r = fluxo.chamar("POST", base, "t-prof", {"descricao": "Extra", "valor_centavos": 100})
    assert r.status_code == 409


# --- nota de material --------------------------------------------------------------------


def test_nota_de_material_calcula_o_total_no_backend(fluxo: Fluxo):  # noqa: F811
    pid = _em_andamento(fluxo)
    url = f"/v1/contratos/{pid}/notas-material"
    corpo = {
        "foto_storage_path": f"{pid}/nota.jpg",
        "itens": [
            {"descricao": "Cano", "quantidade": "2.5", "valor_unitario_centavos": 1_001},
            {"descricao": "Cola", "quantidade": 1, "valor_unitario_centavos": 1_500},
        ],
    }
    r = fluxo.chamar("POST", url, "t-prof", corpo)
    assert r.status_code == 201, r.text
    nota = r.json()
    assert nota["itens"][0]["total_centavos"] == 2_503  # 2,5 x 1001 = 2502,5 -> meio para cima
    assert nota["total_centavos"] == 4_003
    assert fluxo.chamar("POST", url, "t-cliente", corpo).status_code == 403
    assert fluxo.chamar("POST", url, "t-outro-prof", corpo).status_code == 404
    assert fluxo.chamar("GET", url, "t-cliente").json()[0]["id"] == nota["id"]
    assert fluxo.chamar("GET", url, "t-outro-cliente").status_code == 404


@pytest.mark.parametrize(
    "mudanca",
    [
        {"foto_storage_path": "../outro/x.jpg"},
        {"foto_storage_path": "https://x.com/a.jpg"},
        {"itens": []},
        {"itens": [{"descricao": "a", "quantidade": 0, "valor_unitario_centavos": 1}]},
        {"itens": [{"descricao": "a", "quantidade": 1, "valor_unitario_centavos": -1}]},
        {"itens": [{"descricao": "a", "quantidade": 1, "valor_unitario_centavos": 1.5}]},
        {"extra": 1},
    ],
)
def test_nota_de_material_recusa_entrada_ruim(fluxo: Fluxo, mudanca):  # noqa: F811
    pid = _em_andamento(fluxo)
    base = {
        "foto_storage_path": f"{pid}/nota.jpg",
        "itens": [{"descricao": "a", "quantidade": 1, "valor_unitario_centavos": 10}],
    }
    r = fluxo.chamar("POST", f"/v1/contratos/{pid}/notas-material", "t-prof", {**base, **mudanca})
    assert r.status_code == 422


def test_nota_de_material_so_com_servico_em_andamento(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    corpo = {
        "foto_storage_path": f"{pid}/n.jpg",
        "itens": [{"descricao": "a", "quantidade": 1, "valor_unitario_centavos": 10}],
    }
    assert (
        fluxo.chamar("POST", f"/v1/contratos/{pid}/notas-material", "t-prof", corpo).status_code
        == 409
    )


# --- avaliação ---------------------------------------------------------------------------


def test_avaliacao_pelo_contrato_uma_vez_cada_lado(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    url = f"/v1/contratos/{pid}/avaliacao"
    assert (
        fluxo.chamar("POST", url, "t-cliente", {"nota_geral": 5}).status_code == 409
    )  # não concluído
    fluxo.concluir(pid)
    r = fluxo.chamar(
        "POST", url, "t-cliente", {"nota_geral": 5, "comentario": "Ótimo", "etiquetas": []}
    )
    assert r.status_code == 201 and r.json()["direcao"] == "cliente_para_profissional"
    assert fluxo.chamar("POST", url, "t-cliente", {"nota_geral": 4}).status_code == 409
    assert fluxo.chamar("POST", url, "t-prof", {"nota_geral": 4}).status_code == 201
    assert fluxo.chamar("POST", url, "t-outro-cliente", {"nota_geral": 1}).status_code == 404
    assert fluxo.chamar("POST", url, "t-cliente", {"nota_geral": 6}).status_code == 422


# --- perfil ------------------------------------------------------------------------------


def test_me_cria_a_linha_e_patch_troca_o_nome(amb):
    r = chamar(amb, "GET", "/v1/me", "t-cliente")
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["id"] == CLIENTE.id and corpo["papel"] == "cliente"
    assert corpo["papeis"] == ["cliente"] and corpo["tem_perfil_profissional"] is False
    assert chamar(amb, "GET", "/v1/me", "t-cliente").json() == corpo  # idempotente

    r = chamar(amb, "PATCH", "/v1/me", "t-cliente", {"nome": "  Maria   Silva "})
    assert r.status_code == 200 and r.json()["nome"] == "Maria Silva"
    assert chamar(amb, "GET", "/v1/me", "t-cliente").json()["nome"] == "Maria Silva"
    assert chamar(amb, "PATCH", "/v1/me", "t-cliente", {"nome": "a"}).status_code == 422
    assert chamar(amb, "PATCH", "/v1/me", "t-cliente", {"papel": "equipe"}).status_code == 422
    assert chamar(amb, "PATCH", "/v1/me", "t-equipe", {"nome": "Fulano"}).status_code == 403


def test_me_do_profissional_mostra_verificacao(amb):
    usuarios = amb.contexto.usuarios
    from trato.api.auth import PapelUsuario

    usuarios.adicionar(
        PerfilDetalhe(
            PROFISSIONAL.id, "Zé", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 4.8, 12
        )
    )
    usuarios.profissionais.add(PROFISSIONAL.id)
    usuarios.verificacoes[PROFISSIONAL.id] = "em_analise"
    corpo = chamar(amb, "GET", "/v1/me", "t-prof").json()
    assert corpo["papeis"] == ["cliente", "profissional"]
    assert corpo["tem_perfil_profissional"] is True
    assert (
        corpo["status_verificacao"] == "em_analise" and corpo["nivel_verificacao"] == "verificado"
    )
    assert "cpf" not in corpo and "telefone" not in corpo and "email" not in corpo


# --- pedidos abertos e recusa -------------------------------------------------------------


def _abrir(amb, pid, bairro, categoria, faixa, urgente=False, dias=1):
    from trato.api.repositorios import DadosPedido
    from trato.pedidos.estados import Pedido

    p = Pedido(id=pid, cliente_id=CLIENTE.id, aberto_em=AGORA - timedelta(days=dias),
               estado=Estado.ABERTO)  # fmt: skip
    amb.contexto.pedidos.salvar(
        p,
        dados=DadosPedido(
            categoria_id=categoria, cidade_id="c", titulo=f"Pedido {pid}", descricao="d",
            bairro=bairro, faixa_preco_min_centavos=faixa[0], faixa_preco_max_centavos=faixa[1],
            urgente=urgente,
        ),
    )  # fmt: skip


@pytest.fixture
def abertos(amb):
    _abrir(amb, "a", "Centro", "pintura", (10_000, 20_000), dias=1)
    _abrir(amb, "b", "Savassi", "eletrica", (50_000, 90_000), urgente=True, dias=3)
    _abrir(amb, "c", "Centro", "pintura", (None, None), dias=2)
    return amb


def ids(r):
    assert r.status_code == 200, r.text
    return [p["id"] for p in r.json()]


def test_pedidos_abertos_filtros_e_ordem(abertos):
    url = "/v1/profissional/pedidos-abertos"
    assert ids(chamar(abertos, "GET", url, "t-prof")) == ["a", "c", "b"]  # mais recentes primeiro
    assert ids(chamar(abertos, "GET", url + "?categoria_id=pintura", "t-prof")) == ["a", "c"]
    assert ids(chamar(abertos, "GET", url + "?bairro=savassi", "t-prof")) == ["b"]
    assert ids(chamar(abertos, "GET", url + "?preco_min_centavos=60000", "t-prof")) == ["c", "b"]
    assert ids(chamar(abertos, "GET", url + "?preco_max_centavos=30000", "t-prof")) == ["a", "c"]
    assert ids(chamar(abertos, "GET", url + "?ordenar=antigos", "t-prof")) == ["b", "c", "a"]
    assert ids(chamar(abertos, "GET", url + "?ordenar=urgentes", "t-prof"))[0] == "b"
    assert ids(chamar(abertos, "GET", url + "?ordenar=maior_valor", "t-prof"))[0] == "b"
    assert ids(chamar(abertos, "GET", url + "?ordenar=menor_valor", "t-prof"))[0] == "a"
    assert ids(chamar(abertos, "GET", url + "?limite=1", "t-prof")) == ["a"]
    assert chamar(abertos, "GET", url + "?ordenar=aleatorio", "t-prof").status_code == 422
    assert (
        chamar(
            abertos, "GET", url + "?preco_min_centavos=9&preco_max_centavos=1", "t-prof"
        ).status_code
        == 422
    )
    assert chamar(abertos, "GET", url, "t-cliente").status_code == 403


def test_recusar_tira_da_lista_so_dele_e_e_idempotente(abertos):
    url = "/v1/pedidos/a/recusar"
    assert (
        chamar(abertos, "POST", url, "t-prof", {"motivo": "Fora da minha agenda"}).status_code
        == 200
    )
    assert (
        chamar(abertos, "POST", url, "t-prof", {"motivo": "Fora da minha agenda"}).status_code
        == 200
    )
    assert "a" not in ids(chamar(abertos, "GET", "/v1/profissional/pedidos-abertos", "t-prof"))
    assert "a" in ids(chamar(abertos, "GET", "/v1/profissional/pedidos-abertos", "t-outro-prof"))
    # o pedido e o cliente não mudam
    assert abertos.contexto.pedidos.obter("a").estado is Estado.ABERTO
    assert len(abertos.contexto.recusas.do_profissional(PROFISSIONAL.id)) == 1


def test_recusar_exige_profissional_motivo_e_pedido_visivel(abertos):
    url = "/v1/pedidos/a/recusar"
    assert chamar(abertos, "POST", url, "t-cliente", {"motivo": "x"}).status_code == 403
    assert chamar(abertos, "POST", url, "t-prof", {"motivo": ""}).status_code == 422
    assert chamar(abertos, "POST", url, "t-prof", {}).status_code == 422
    assert chamar(abertos, "POST", url, "t-prof", {"motivo": "x" * 501}).status_code == 422
    assert (
        chamar(
            abertos, "POST", "/v1/pedidos/nao-existe/recusar", "t-prof", {"motivo": "x"}
        ).status_code
        == 404
    )
