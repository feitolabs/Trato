"""Cada rota que o `ApiAdminHttp` (admin/lib/dados/api_http.dart) chama, com o corpo que ele manda e as
chaves que ele lê da resposta. Se o backend mudar o formato, o painel quebra aqui antes de quebrar na tela."""

from __future__ import annotations

import pytest

from .conftest import amb


def _tem(obj: dict, *chaves: str) -> None:
    faltam = [c for c in chaves if c not in obj]
    assert not faltam, f"o painel lê {faltam} e a resposta não tem: {sorted(obj)}"


# ---------- login ----------


def test_login_supabase_e_eu(painel):
    r = painel.http.post(
        "/auth/v1/token", params={"grant_type": "password"},
        json={"email": amb.email_de("mediador"), "password": amb.SENHA_TESTE},
    )  # fmt: skip
    assert isinstance(r.json()["access_token"], str)
    eu = painel.chamar("mediador", "GET", "/v1/admin/eu")
    assert eu.status_code == 200, eu.text
    _tem(eu.json(), "id", "papel", "alcada_centavos")
    assert eu.json()["papel"] == "mediador"
    assert eu.json()["alcada_centavos"] == 200_000


def test_eu_sem_token_ou_token_invalido(painel):
    assert painel.chamar(None, "GET", "/v1/admin/eu").status_code == 401
    r = painel.http.get("/v1/admin/eu", headers={"Authorization": "Bearer t-invalido"})
    assert r.status_code == 401


@pytest.mark.parametrize(
    "papel", ["cadastro", "seguranca", "administrador", "financeiro", "atendente_n1", "dpo"]
)
def test_eu_devolve_o_papel_certo_para_cada_conta(painel, papel):
    assert painel.chamar(papel, "GET", "/v1/admin/eu").json()["papel"] == papel


# ---------- verificações ----------


def test_verificacoes_lista_documento_e_decisao(painel):
    lista = painel.chamar("cadastro", "GET", "/v1/admin/verificacoes", params={"limite": "100"})
    assert lista.status_code == 200
    itens = lista.json()["itens"]
    assert len(itens) == 2
    v = itens[0]
    _tem(
        v,
        "id",
        "profissional_nome",
        "nivel_solicitado",
        "status",
        "enviada_em",
        "cpf_mascarado",
        "documentos",
    )
    assert v["cpf_mascarado"].startswith("***.")
    doc = v["documentos"][0]
    _tem(doc, "id", "tipo")
    assert "bucket" not in str(v)

    r = painel.chamar(
        "cadastro", "POST", f"/v1/admin/verificacoes/{v['id']}/documentos/{doc['id']}/url",
        json={"motivo": "Conferir o documento"},
    )  # fmt: skip
    assert r.status_code == 200, r.text
    _tem(r.json(), "url", "expira_em_segundos")
    assert r.json()["expira_em_segundos"] <= 60
    assert "bucket" not in r.json()["url"]

    r = painel.chamar(
        "cadastro",
        "POST",
        f"/v1/admin/verificacoes/{v['id']}/decisao",
        json={"aprovar": False, "motivo": "Documento ilegível"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "recusada"
    assert r.json()["motivo_recusa"] == "Documento ilegível"
    r2 = painel.chamar(
        "cadastro",
        "POST",
        f"/v1/admin/verificacoes/{v['id']}/decisao",
        json={"aprovar": True, "motivo": "Mudei de ideia"},
    )
    assert r2.status_code == 409


def test_verificacao_aprovar(painel):
    vid = painel.chamar("cadastro", "GET", "/v1/admin/verificacoes").json()["itens"][1]["id"]
    r = painel.chamar(
        "cadastro",
        "POST",
        f"/v1/admin/verificacoes/{vid}/decisao",
        json={"aprovar": True, "motivo": "Tudo conferido"},
    )
    assert r.status_code == 200 and r.json()["status"] == "aprovada"


@pytest.mark.parametrize("papel", ["seguranca", "administrador"])
def test_so_cadastro_decide_e_abre_documento(painel, papel):
    v = painel.chamar("cadastro", "GET", "/v1/admin/verificacoes").json()["itens"][0]
    assert painel.chamar(papel, "GET", "/v1/admin/verificacoes").status_code == 200  # ver pode
    r = painel.chamar(
        papel,
        "POST",
        f"/v1/admin/verificacoes/{v['id']}/decisao",
        json={"aprovar": True, "motivo": "Tentando"},
    )
    assert r.status_code == 403
    caminho = f"/v1/admin/verificacoes/{v['id']}/documentos/{v['documentos'][0]['id']}/url"
    assert painel.chamar(papel, "POST", caminho, json={"motivo": "Tentando"}).status_code == 403


def test_verificacao_motivo_obrigatorio_422_401_403(painel):
    v = painel.chamar("cadastro", "GET", "/v1/admin/verificacoes").json()["itens"][0]
    r = painel.chamar(
        "cadastro",
        "POST",
        f"/v1/admin/verificacoes/{v['id']}/decisao",
        json={"aprovar": True, "motivo": "  "},
    )
    assert r.status_code == 422
    assert painel.chamar(None, "GET", "/v1/admin/verificacoes").status_code == 401
    assert painel.chamar("financeiro", "GET", "/v1/admin/verificacoes").status_code == 403


# ---------- disputas ----------


def test_disputas_lista_e_detalhe_no_formato_do_painel(painel):
    lista = painel.chamar("mediador", "GET", "/v1/admin/disputas", params={"limite": "100"})
    assert lista.status_code == 200
    assert {d["pedido_id"] for d in lista.json()["itens"]} == {"ped-1", "ped-2"}
    d = painel.chamar("mediador", "GET", "/v1/admin/disputas/ped-1").json()
    _tem(d, "pedido_id", "cliente", "profissional", "motivo", "valor_congelado_centavos", "decisao_ate", "estado",
         "decisao", "divisao", "decidido_por", "evidencias", "linha_do_tempo")  # fmt: skip
    _tem(d["cliente"], "nome")
    for e in d["evidencias"]:
        _tem(e, "ator_papel", "origem", "dados")
        assert "1234" not in str(e) and "9876" not in str(e)  # códigos de check-in/out nunca
    for e in d["linha_do_tempo"]:
        _tem(e, "em", "acao", "ator_papel", "de", "para")


def test_disputa_dentro_da_alcada_decide_na_hora(painel):
    r = painel.chamar("mediador", "POST", "/v1/admin/disputas/ped-1/decisao", json={
        "resultado": "reembolso_parcial", "justificativa": "Foto mostra o defeito", "valor_cliente_centavos": 40_000})  # fmt: skip
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "decidida"
    assert r.json()["divisao"]["para_cliente_centavos"] == 40_000


def test_disputa_acima_da_alcada_pede_segunda_pessoa(painel):
    r = painel.chamar("mediador", "POST", "/v1/admin/disputas/ped-2/decisao", json={
        "resultado": "reembolso_total", "justificativa": "Serviço não foi feito"})  # fmt: skip
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "aguardando_aprovacao"
    assert (
        painel.chamar(
            "mediador",
            "POST",
            "/v1/admin/disputas/ped-2/aprovacao",
            json={"justificativa": "Eu mesmo"},
        ).status_code
        == 403
    )
    assert (
        painel.chamar(
            "financeiro",
            "POST",
            "/v1/admin/disputas/ped-2/aprovacao",
            json={"justificativa": "Não posso"},
        ).status_code
        == 403
    )
    r = painel.chamar(
        "lider_suporte",
        "POST",
        "/v1/admin/disputas/ped-2/aprovacao",
        json={"justificativa": "Confere com as provas"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "decidida"
    assert r.json()["decisao"] == "reembolso_total"


def test_disputa_422_401_403_404(painel):
    corpo = {"resultado": "reembolso_parcial", "justificativa": "sem valor"}
    assert (
        painel.chamar(
            "mediador", "POST", "/v1/admin/disputas/ped-1/decisao", json=corpo
        ).status_code
        == 422
    )
    assert (
        painel.chamar(
            "mediador",
            "POST",
            "/v1/admin/disputas/ped-1/decisao",
            json={"resultado": "x", "justificativa": "valor inválido"},
        ).status_code
        == 422
    )
    assert painel.chamar(None, "GET", "/v1/admin/disputas").status_code == 401
    assert painel.chamar("cadastro", "GET", "/v1/admin/disputas").status_code == 403
    assert (
        painel.chamar(
            "atendente_n2",
            "POST",
            "/v1/admin/disputas/ped-1/decisao",
            json={"resultado": "liberar_tudo", "justificativa": "Não pode"},
        ).status_code
        == 403
    )
    assert painel.chamar("mediador", "GET", "/v1/admin/disputas/nao-existe").status_code == 404


# ---------- pagamentos (somente leitura) ----------


def test_pagamentos_resumo_e_extrato(painel):
    r = painel.chamar("financeiro", "GET", "/v1/admin/pagamentos/resumo")
    assert r.status_code == 200
    _tem(
        r.json(),
        "confirmado_centavos",
        "estornado_centavos",
        "retido_centavos",
        "divergencias",
        "atualizado_em",
    )
    assert r.json()["divergencias"] == 1
    itens = painel.chamar(
        "financeiro", "GET", "/v1/admin/pagamentos", params={"limite": "100"}
    ).json()["itens"]
    assert len(itens) == 3
    for p in itens:
        _tem(
            p,
            "lancamento_id",
            "data",
            "valor_centavos",
            "status",
            "pedido_id",
            "referencia_provedor",
            "divergente",
        )
        assert isinstance(p["valor_centavos"], int)
    assert any(p["divergente"] for p in itens)


@pytest.mark.parametrize("metodo", ["POST", "PUT", "PATCH", "DELETE"])
def test_pagamentos_nao_tem_escrita(painel, metodo):
    assert painel.chamar("administrador", metodo, "/v1/admin/pagamentos", json={}).status_code in (
        404,
        405,
    )


def test_pagamentos_401_403(painel):
    assert painel.chamar(None, "GET", "/v1/admin/pagamentos/resumo").status_code == 401
    assert painel.chamar("mediador", "GET", "/v1/admin/pagamentos").status_code == 403


# ---------- busca ----------


def test_busca_de_usuarios_pedidos_e_dados_pessoais(painel):
    us = painel.chamar(
        "atendente_n1", "GET", "/v1/admin/usuarios", params={"q": "Maria", "limite": "100"}
    ).json()["itens"]
    assert us and all(k in us[0] for k in ("id", "nome", "tipo", "status"))
    assert "cpf" not in us[0] and "telefone" not in us[0]
    assert (
        painel.chamar("atendente_n1", "GET", "/v1/admin/usuarios", params={"q": "a"}).status_code
        == 422
    )
    ped = painel.chamar(
        "atendente_n1", "GET", "/v1/admin/pedidos", params={"q": "ped", "limite": "100"}
    )
    assert ped.status_code == 200, ped.text
    for p in ped.json()["itens"]:
        _tem(p, "id", "titulo", "cliente_nome", "estado", "valor_centavos")
    r = painel.chamar(
        "cadastro",
        "POST",
        "/v1/admin/usuarios/cli-1/dados-pessoais",
        json={"motivo": "Validar cadastro"},
    )
    assert r.status_code == 200
    _tem(r.json(), "cpf", "telefone", "data_nascimento")
    assert (
        painel.chamar(
            "atendente_n1",
            "POST",
            "/v1/admin/usuarios/cli-1/dados-pessoais",
            json={"motivo": "Curiosidade"},
        ).status_code
        == 403
    )
    assert (
        painel.chamar(
            "cadastro", "POST", "/v1/admin/usuarios/cli-1/dados-pessoais", json={}
        ).status_code
        == 422
    )


# ---------- configuração ----------


def test_config_definicoes_versoes_e_detalhe(painel):
    defs = painel.chamar("financeiro", "GET", "/v1/admin/config/definicoes").json()
    assert isinstance(defs, list) and defs
    _tem(defs[0], "chave", "descricao", "unidade", "minimo", "maximo", "exige_dupla_aprovacao")
    lista = painel.chamar(
        "financeiro", "GET", "/v1/admin/config/versoes", params={"limite": "10"}
    ).json()
    assert len(lista) == 2
    d = painel.chamar("financeiro", "GET", f"/v1/admin/config/versoes/{lista[0]['id']}").json()
    _tem(
        d,
        "id",
        "numero",
        "status",
        "motivo",
        "criada_por",
        "criado_em",
        "aprovada_por",
        "parametros",
    )
    _tem(d["parametros"][0], "chave", "valor", "escopo_tipo")


def test_config_aprovacao_dupla_do_painel(painel):
    """Como o painel faz: propor (cria + envia); outra pessoa aprova e publica."""
    c = painel.chamar("financeiro", "POST", "/v1/admin/config/versoes", json={
        "motivo": "Reduzir adiantamento", "partir_da_vigente": True,
        "parametros": [{"chave": "adiantamento_bps", "valor": 2500}]})  # fmt: skip
    assert c.status_code == 201, c.text
    vid = c.json()["id"]
    e = painel.chamar(
        "financeiro",
        "POST",
        f"/v1/admin/config/versoes/{vid}/enviar",
        json={"motivo": "Reduzir adiantamento"},
    )
    assert e.status_code == 200 and e.json()["status"] == "aguardando_aprovacao"
    assert (
        painel.chamar(
            "financeiro",
            "POST",
            f"/v1/admin/config/versoes/{vid}/aprovar",
            json={"motivo": "Eu mesmo"},
        ).status_code
        == 403
    )
    a = painel.chamar(
        "administrador",
        "POST",
        f"/v1/admin/config/versoes/{vid}/aprovar",
        json={"motivo": "Conferi os números"},
    )
    assert a.status_code == 200 and a.json()["status"] == "aprovada"
    p = painel.chamar(
        "administrador",
        "POST",
        f"/v1/admin/config/versoes/{vid}/publicar",
        json={"motivo": "Publicar agora"},
    )
    assert p.status_code == 200 and p.json()["status"] == "vigente"
    assert painel.chamar("financeiro", "GET", "/v1/admin/config/vigente").json()["id"] == vid
    rev = painel.chamar(
        "financeiro",
        "POST",
        f"/v1/admin/config/versoes/{vid}/reverter",
        json={"motivo": "Voltar atrás"},
    )
    assert rev.status_code == 201 and rev.json()["status"] == "aguardando_aprovacao"


def test_config_422_401_403(painel):
    r = painel.chamar("financeiro", "POST", "/v1/admin/config/versoes", json={
        "motivo": "Fora da faixa", "parametros": [{"chave": "adiantamento_bps", "valor": 99_999}]})  # fmt: skip
    assert r.status_code == 422
    assert painel.chamar(None, "GET", "/v1/admin/config/definicoes").status_code == 401
    assert painel.chamar("cadastro", "GET", "/v1/admin/config/definicoes").status_code == 403


# ---------- auditoria ----------


def test_auditoria_lista_e_verificar_cadeia(painel):
    painel.chamar(
        "cadastro",
        "POST",
        "/v1/admin/usuarios/cli-1/dados-pessoais",
        json={"motivo": "Validar cadastro"},
    )
    itens = painel.chamar(
        "seguranca", "GET", "/v1/admin/auditoria", params={"acao": "dado_pessoal.", "limite": "100"}
    ).json()["itens"]
    assert itens
    _tem(
        itens[0],
        "id",
        "ocorrida_em",
        "ator_id",
        "ator_tipo",
        "acao",
        "entidade",
        "entidade_id",
        "motivo",
    )
    r = painel.chamar("seguranca", "POST", "/v1/admin/auditoria/verificar-cadeia")
    assert r.status_code == 200
    _tem(r.json(), "integra", "primeira_falha_id")
    assert r.json()["integra"] is True
    assert painel.chamar("financeiro", "GET", "/v1/admin/auditoria").status_code == 403
    assert painel.chamar(None, "POST", "/v1/admin/auditoria/verificar-cadeia").status_code == 401


def test_cadeia_adulterada_e_detectada(painel, ambiente):
    painel.chamar(
        "cadastro",
        "POST",
        "/v1/admin/usuarios/cli-1/dados-pessoais",
        json={"motivo": "Validar cadastro"},
    )
    itens = painel.chamar("seguranca", "GET", "/v1/admin/auditoria").json()["itens"]
    ambiente.admin.auditoria.adulterar_para_teste(itens[-1]["id"], motivo="adulterado")
    r = painel.chamar("seguranca", "POST", "/v1/admin/auditoria/verificar-cadeia").json()
    assert r["integra"] is False and r["primeira_falha_id"] is not None


# ---------- o que o painel nunca deve receber ----------


def test_nenhuma_resposta_vaza_caminho_de_storage_codigo_ou_cpf_cheio(painel):
    textos = []
    for papel, caminho in (
        ("cadastro", "/v1/admin/verificacoes"), ("mediador", "/v1/admin/disputas/ped-1"),
        ("atendente_n1", "/v1/admin/usuarios?q=Maria"), ("atendente_n1", "/v1/admin/pedidos?q=ped"),
        ("atendente_n1", "/v1/admin/pedidos/ped-1"), ("financeiro", "/v1/admin/webhooks/eventos"),
    ):  # fmt: skip
        r = painel.chamar(papel, "GET", caminho)
        assert r.status_code == 200, (caminho, r.text)
        textos.append(r.text)
    todo = "\n".join(textos)
    for proibido in (
        "bucket-privado",
        "123.456.789-09",
        "+5531999990000",
        "codigo_inicio",
        "codigo_conclusao",
        '"1234"',
        '"9876"',
    ):
        assert proibido not in todo, proibido
