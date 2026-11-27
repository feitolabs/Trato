"""Etapa 2b: `POST /v1/cadastro/vincular` sem abuso e maioridade (Termos 4.1) atrás de chave."""

from __future__ import annotations

from datetime import date, timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - app com o pagamento instalado

from trato.api.maioridade import MENOR, SEM_DATA, idade
from trato.pedidos.estados import Estado
from trato.seguranca.config import obter_config_seguranca

URL = "/v1/cadastro/vincular"
CPF = "12345678909"
OUTRO_CPF = "52998224725"


def vincular(amb, usuario="novo-1", email="nova@email.com", token=None, **extra):
    corpo = {"usuario_id": usuario, "email": email, "nome": "Nova", **extra}
    return amb.cliente.post(URL, json=corpo, headers=cab(token) if token else {})


def gravou(amb, usuario="novo-1") -> bool:
    return amb.contexto.usuarios.tem_cpf(usuario)


# --- vínculo sem sessão ------------------------------------------------------------------------


def test_conta_nova_que_nunca_entrou_grava(amb):
    r = vincular(amb, cpf=CPF, data_nascimento="1990-01-01")
    assert r.status_code == 204 and gravou(amb)
    assert amb.contexto.usuarios.data_nascimento("novo-1") == date(1990, 1, 1)


@pytest.mark.parametrize("caso", ["ja_entrou", "conta_antiga", "outro_email"])
def test_recusa_responde_igual_e_nao_grava(amb, caso):
    usuarios = amb.contexto.usuarios
    if caso == "ja_entrou":
        usuarios.acessos.add("novo-1")
    elif caso == "conta_antiga":
        usuarios.criadas_em["novo-1"] = AGORA - timedelta(minutes=61)
    else:
        usuarios.emails["novo-1"] = "dona@email.com"
    r = vincular(amb, cpf=CPF)
    assert r.status_code == 204 and r.content == b"" and not gravou(amb)


def test_no_limite_da_janela_ainda_grava(amb):
    amb.contexto.usuarios.criadas_em["novo-1"] = AGORA - timedelta(minutes=60)
    assert vincular(amb, cpf=CPF).status_code == 204 and gravou(amb)


def test_cpf_de_outra_conta_nao_e_revelado_sem_sessao(amb):
    amb.contexto.usuarios.registrar_dados_privados("dona", CPF)
    r = vincular(amb, cpf=CPF, data_nascimento="1990-01-01")
    assert r.status_code == 204 and not gravou(amb)
    assert amb.contexto.usuarios.data_nascimento("novo-1") == date(1990, 1, 1)


def test_tentativas_por_conta_sao_limitadas_e_valem_para_conta_inexistente(amb):
    for usuario in ("novo-1", "nao-existe"):
        amb.contexto.usuarios.acessos.add("novo-1")
        codigos = [vincular(amb, usuario).status_code for _ in range(6)]
        assert codigos == [204] * 5 + [429]
    assert vincular(amb, "NOVO-1").status_code == 429  # a mesma conta escrita de outro jeito
    amb.relogio.avancar(hours=2)
    assert vincular(amb, "novo-1").status_code == 204


# --- vínculo com sessão (Google/Apple logado, ou e-mail sem confirmação) -----------------------


def test_com_sessao_grava_a_propria_conta_mesmo_antiga_e_ja_usada(amb):
    amb.contexto.usuarios.acessos.add(CLIENTE.id)
    for _ in range(8):  # logado não conta no limite por conta
        r = vincular(amb, CLIENTE.id, "mariana@email.com", "t-cliente", cpf=CPF)
        assert r.status_code == 204
    assert gravou(amb, CLIENTE.id)


SESSAO_DE_OUTRA_PESSOA = "t-cliente"
SESSAO_INVALIDA = "vencido"


def test_com_sessao_de_outra_pessoa_nao_grava_nada(amb):
    r = vincular(amb, "novo-1", token=SESSAO_DE_OUTRA_PESSOA, cpf=CPF)  # noqa: S106 - token falso
    assert r.status_code == 204 and not gravou(amb) and not gravou(amb, CLIENTE.id)


def test_token_invalido_vale_como_sem_sessao(amb):
    amb.contexto.usuarios.acessos.add("novo-1")
    r = vincular(amb, token=SESSAO_INVALIDA, cpf=CPF)  # noqa: S106 - token falso
    assert r.status_code == 204 and not gravou(amb)


# --- maioridade --------------------------------------------------------------------------------

ROTAS = [
    ("t-cliente", "/v1/pedidos"),
    ("t-prof", "/v1/pedidos/ped-1/orcamentos"),
    ("t-cliente", "/v1/pedidos/ped-1/cobranca"),
    ("t-cliente", "/v1/contratos/ped-1/cobranca"),
    ("t-cliente", "/v1/pedidos/ped-1/aditivos/a1/aprovacao"),
    ("t-cliente", "/v1/contratos/ped-1/aditivos/a1/aprovar"),
    ("t-prof", "/v1/pedidos/ped-1/orcamentos/orc-1/contraproposta/aceitar"),
    ("t-prof", "/v1/pedidos/ped-1/orcamentos/orc-1/propor"),
    ("t-cliente", "/v1/profissional/cadastro"),
    ("t-cliente", "/v1/recorrencias"),
    ("t-prof", "/v1/recorrencias/r1/aceitar"),
]


@pytest.fixture
def ligada(monkeypatch):
    monkeypatch.setattr(obter_config_seguranca(), "exigir_maioridade", True)


def nascido(anos: int, dias: int = 0) -> date:
    hoje = AGORA.date()
    return hoje.replace(year=hoje.year - anos) + timedelta(days=dias)


def definir_nascimento(amb, quando: date | None) -> None:
    for usuario in (CLIENTE.id, PROFISSIONAL.id):
        amb.contexto.usuarios.nascimentos.pop(usuario, None)
        if quando is not None:
            amb.contexto.usuarios.nascimentos[usuario] = quando


def chamar(amb, token, url):
    return amb.cliente.post(url, json={}, headers=cab(token))


def codigo(resposta):
    corpo = resposta.json()
    return corpo.get("codigo") if isinstance(corpo, dict) else None


def test_chave_desligada_por_padrao():
    assert obter_config_seguranca().exigir_maioridade is False


@pytest.mark.parametrize("token,url", ROTAS)
def test_ligada_recusa_sem_data_e_menor_e_libera_maior(fluxo, ligada, token, url):  # noqa: F811
    amb = fluxo.amb
    amb.semear_pedido(Estado.ABERTO)
    for quando, esperado in ((None, SEM_DATA), (nascido(18, 1), MENOR)):
        definir_nascimento(amb, quando)
        r = chamar(amb, token, url)
        assert r.status_code == 422 and codigo(r) == esperado, (url, r.text)
        assert r.json()["detail"]
    definir_nascimento(amb, nascido(18))  # faz 18 hoje
    assert codigo(chamar(amb, token, url)) not in (SEM_DATA, MENOR)


@pytest.mark.parametrize("token,url", ROTAS)
def test_desligada_nao_exige_data(fluxo, token, url):  # noqa: F811
    amb = fluxo.amb
    amb.semear_pedido(Estado.ABERTO)
    definir_nascimento(amb, None)
    assert codigo(chamar(amb, token, url)) not in (SEM_DATA, MENOR)


def test_sem_login_continua_401(amb, ligada):
    assert amb.cliente.post("/v1/pedidos", json={}).status_code == 401


@pytest.mark.parametrize(
    "nascimento,hoje,anos",
    [
        (date(2008, 2, 29), date(2026, 2, 28), 17),
        (date(2008, 2, 29), date(2026, 3, 1), 18),
        (date(2008, 11, 25), date(2026, 11, 25), 18),
        (date(2008, 11, 26), date(2026, 11, 25), 17),
    ],
)
def test_idade_nas_bordas(nascimento, hoje, anos):
    assert idade(nascimento, hoje) == anos
