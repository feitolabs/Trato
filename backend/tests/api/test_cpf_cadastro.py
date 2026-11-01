"""Cadastro com CPF: consulta antes do cadastro e gravação única (um CPF, uma conta)."""

from __future__ import annotations

from conftest import cab

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
