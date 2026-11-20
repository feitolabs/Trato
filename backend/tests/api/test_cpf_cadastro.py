"""Cadastro com CPF: consulta antes do cadastro e gravação única (um CPF, uma conta)."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import date, timedelta
from uuid import uuid4

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab

from trato.api.repositorios import Orcamento
from trato.api.rotas_pagamento import instalar_pagamento
from trato.pagamentos.memoria import AditivosEmMemoria, CobrancasEmMemoria
from trato.pagamentos.modelos import ConfigPagamento
from trato.pagamentos.orquestrador import ServicoPagamento
from trato.pagamentos.provedor import ProvedorFake
from trato.pedidos.estados import Estado as E
from trato.persistencia.usuarios import UsuariosPostgres

CPF = "123.456.789-09"
CPF_DIGITOS = "12345678909"


def consultar(amb, cpf: str = CPF):
    return amb.cliente.post("/v1/cadastro/cpf", json={"cpf": cpf})


def gravar(amb, token: str, cpf: str = CPF):
    return amb.cliente.post("/v1/me/dados-pessoais", json={"cpf": cpf}, headers=cab(token))


def test_consulta_publica_diz_se_o_cpf_esta_livre_sem_login(amb):
    r = consultar(amb)
    assert r.status_code == 200
    assert r.json() == {"disponivel": True}


def test_consulta_recusa_cpf_invalido(amb):
    assert consultar(amb, "123.456.789-01").status_code == 422
    assert consultar(amb, "111.111.111-11").status_code == 422
    assert consultar(amb, "123456789").status_code == 422


def test_gravar_cpf_ocupa_e_repetir_na_mesma_conta_e_idempotente(amb):
    assert gravar(amb, "t-cliente").status_code == 204
    assert consultar(amb).json() == {"disponivel": False}
    assert gravar(amb, "t-cliente").status_code == 204
    assert consultar(amb).json() == {"disponivel": False}


def test_cpf_de_outra_conta_responde_409(amb):
    assert gravar(amb, "t-cliente").status_code == 204
    r = gravar(amb, "t-outro-cliente")
    assert r.status_code == 409
    assert r.json()["detail"] == "Este CPF já está cadastrado em outra conta."


def test_gravar_exige_login(amb):
    r = amb.cliente.post("/v1/me/dados-pessoais", json={"cpf": CPF})
    assert r.status_code == 401


def test_cpf_com_e_sem_formatacao_e_o_mesmo(amb):
    assert gravar(amb, "t-cliente", CPF).status_code == 204
    assert consultar(amb, CPF_DIGITOS).json() == {"disponivel": False}
    assert consultar(amb, CPF).json() == {"disponivel": False}


def test_vincular_e_resolver_identificador_por_cpf_e_telefone(amb):
    r_vinc = amb.cliente.post(
        "/v1/cadastro/vincular",
        json={
            "usuario_id": "cli-1",
            "email": "mariana@email.com",
            "nome": "Mariana Alves",
            "cpf": CPF,
            "telefone": "+5531987654417",
        },
    )
    assert r_vinc.status_code == 204

    r_cpf = amb.cliente.post("/v1/cadastro/identificador", json={"identificador": CPF})
    assert r_cpf.status_code == 200
    assert r_cpf.json() == {"email": "mariana@email.com"}

    r_tel = amb.cliente.post(
        "/v1/cadastro/identificador", json={"identificador": "(31) 98765-4417"}
    )
    assert r_tel.status_code == 200
    assert r_tel.json() == {"email": "mariana@email.com"}

    r_inexistente = amb.cliente.post(
        "/v1/cadastro/identificador", json={"identificador": "99999999999"}
    )
    assert r_inexistente.status_code == 200
    assert r_inexistente.json() == {"email": None}


def test_vincular_sem_cpf_e_perfil_expoe_cpf_cadastrado(amb):
    r_vinc = amb.cliente.post(
        "/v1/cadastro/vincular",
        json={
            "usuario_id": "cli-sem-cpf",
            "email": "semcpf@email.com",
            "nome": "Joana",
            "telefone": "+5531987650000",
        },
    )
    assert r_vinc.status_code == 204
    assert amb.contexto.usuarios.tem_cpf("cli-sem-cpf") is False

    # Perfil /v1/me mostra cpf_cadastrado=False sem vazar CPF, e vira True após POST /v1/me/cpf.
    me_antes = amb.cliente.get("/v1/me", headers=cab("t-cliente"))
    assert me_antes.status_code == 200
    assert me_antes.json()["cpf_cadastrado"] is False
    assert "cpf" not in me_antes.json()

    nasc_ok = (date.today() - timedelta(days=365 * 25)).isoformat()
    menor = (date.today() - timedelta(days=365 * 17)).isoformat()
    assert (
        amb.cliente.post(
            "/v1/me/cpf",
            json={"cpf": CPF, "data_nascimento": menor},
            headers=cab("t-cliente"),
        ).status_code
        == 422
    )
    r_ok = amb.cliente.post(
        "/v1/me/cpf",
        json={"cpf": CPF, "data_nascimento": nasc_ok},
        headers=cab("t-cliente"),
    )
    assert r_ok.status_code == 204

    me_depois = amb.cliente.get("/v1/me", headers=cab("t-cliente"))
    assert me_depois.status_code == 200
    assert me_depois.json()["cpf_cadastrado"] is True
    assert "cpf" not in me_depois.json()

    # 1 CPF por conta: outra conta recebe 409.
    r_dup = amb.cliente.post(
        "/v1/me/cpf",
        json={"cpf": CPF, "data_nascimento": nasc_ok},
        headers=cab("t-outro-cliente"),
    )
    assert r_dup.status_code == 409


def test_pagamento_bloqueado_sem_cpf_e_liberado_apos_post_me_cpf(amb):
    fake = ProvedorFake()
    servico = ServicoPagamento(
        fake,
        lambda: ConfigPagamento(),
        CobrancasEmMemoria(),
        AditivosEmMemoria(),
    )
    instalar_pagamento(amb.cliente.app, amb.contexto, servico)

    amb.semear_pedido(E.ORCAMENTO_ACEITO, id="ped-sem-cpf", cliente_id=CLIENTE.id)
    amb.contexto.orcamentos.adicionar(
        Orcamento("orc-1", "ped-sem-cpf", PROFISSIONAL.id, 100_000, "pintura")
    )

    # Sem CPF, as duas rotas de cobrança devolvem 422 cpf_obrigatorio.
    r1 = amb.cliente.post(
        "/v1/pedidos/ped-sem-cpf/cobranca", json={"meio": "pix"}, headers=cab("t-cliente")
    )
    assert r1.status_code == 422
    assert r1.json() == {
        "detail": "Informe seu CPF para concluir o pagamento.",
        "codigo": "cpf_obrigatorio",
    }
    r2 = amb.cliente.post(
        "/v1/contratos/ped-sem-cpf/cobranca", json={"meio": "pix"}, headers=cab("t-cliente")
    )
    assert r2.status_code == 422
    assert r2.json() == {
        "detail": "Informe seu CPF para concluir o pagamento.",
        "codigo": "cpf_obrigatorio",
    }

    # Cadastra CPF via POST /v1/me/cpf e tenta pagar de novo.
    nasc_ok = (date.today() - timedelta(days=365 * 20)).isoformat()
    assert (
        amb.cliente.post(
            "/v1/me/cpf",
            json={"cpf": CPF, "data_nascimento": nasc_ok},
            headers=cab("t-cliente"),
        ).status_code
        == 204
    )
    ok_ped = amb.cliente.post(
        "/v1/pedidos/ped-sem-cpf/cobranca", json={"meio": "pix"}, headers=cab("t-cliente")
    )
    assert ok_ped.status_code == 201, ok_ped.text


def test_postgres_usuarios_tem_cpf_e_preenche_cpf_nulo_depois():
    uid = str(uuid4())
    executadas = []

    class Con:
        def __init__(self, row):
            self._row = row

        def execute(self, sql, params=()):
            executadas.append((sql, params))
            return self

        def fetchone(self):
            return self._row

    class Banco:
        def __init__(self, row=None):
            self._row = row

        @contextmanager
        def transacao(self):
            yield Con(self._row)

    assert UsuariosPostgres(Banco(row=None)).tem_cpf(uid) is False
    assert UsuariosPostgres(Banco(row={"?column?": 1})).tem_cpf(uid) is True
    assert UsuariosPostgres(Banco(row=None)).registrar_dados_privados(uid, CPF_DIGITOS) is False
    assert any("set cpf = %s" in sql and "cpf is null" in sql for sql, _ in executadas)
    # _unused evita lint de AGORA
    assert AGORA is not None
