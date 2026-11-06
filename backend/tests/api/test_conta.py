"""Conta: dados pessoais, endereços salvos, favoritos e contatos de confiança (`/v1/me/...`)."""

from __future__ import annotations

from conftest import cab

END = {
    "apelido": "Casa",
    "cep": "01310-100",
    "logradouro": "Av. Paulista",
    "numero": "1000",
    "bairro": "Bela Vista",
    "cidade": "São Paulo",
    "uf": "sp",
}


def test_exige_login(amb):
    for rota in ("dados-pessoais", "enderecos", "favoritos", "contatos-confianca"):
        assert amb.cliente.get(f"/v1/me/{rota}").status_code == 401


def test_dados_pessoais_telefone_e_nascimento(amb):
    h = cab("t-cliente")
    r = amb.cliente.patch(
        "/v1/me/dados-pessoais", json={"telefone": "(11) 98888-7777", "data_nascimento": "1990-05-10"},
        headers=h,
    )  # fmt: skip
    assert r.status_code == 200, r.text
    assert r.json()["telefone"] == "11988887777"
    assert (
        amb.cliente.get("/v1/me/dados-pessoais", headers=h).json()["data_nascimento"]
        == "1990-05-10"
    )
    r = amb.cliente.patch("/v1/me/dados-pessoais", json={"remover_telefone": True}, headers=h)
    assert r.json()["telefone"] is None
    assert r.json()["data_nascimento"] == "1990-05-10"


def test_telefone_invalido_e_duplicado(amb):
    h = cab("t-cliente")
    assert (
        amb.cliente.patch("/v1/me/dados-pessoais", json={"telefone": "123"}, headers=h).status_code
        == 422
    )
    ok = {"telefone": "11988887777"}
    assert amb.cliente.patch("/v1/me/dados-pessoais", json=ok, headers=h).status_code == 200
    r = amb.cliente.patch("/v1/me/dados-pessoais", json=ok, headers=cab("t-outro-cliente"))
    assert r.status_code == 409


def test_enderecos_primeiro_vira_principal_e_so_um(amb):
    h = cab("t-cliente")
    a = amb.cliente.post("/v1/me/enderecos", json=END, headers=h).json()
    assert a["principal"] is True and a["cep"] == "01310100" and a["uf"] == "SP"
    b = amb.cliente.post("/v1/me/enderecos", json={**END, "apelido": "Trabalho"}, headers=h).json()
    assert b["principal"] is False
    r = amb.cliente.put(
        f"/v1/me/enderecos/{b['id']}", json={**END, "apelido": "Trabalho", "principal": True},
        headers=h,
    )  # fmt: skip
    assert r.json()["principal"] is True
    lista = amb.cliente.get("/v1/me/enderecos", headers=h).json()
    assert [e["principal"] for e in lista].count(True) == 1


def test_endereco_remover_passa_o_principal_adiante(amb):
    h = cab("t-cliente")
    a = amb.cliente.post("/v1/me/enderecos", json=END, headers=h).json()
    amb.cliente.post("/v1/me/enderecos", json={**END, "apelido": "Outro"}, headers=h)
    assert amb.cliente.delete(f"/v1/me/enderecos/{a['id']}", headers=h).status_code == 204
    lista = amb.cliente.get("/v1/me/enderecos", headers=h).json()
    assert len(lista) == 1 and lista[0]["principal"] is True
    assert amb.cliente.delete(f"/v1/me/enderecos/{a['id']}", headers=h).status_code == 404


def test_endereco_e_so_do_dono(amb):
    a = amb.cliente.post("/v1/me/enderecos", json=END, headers=cab("t-cliente")).json()
    outro = cab("t-outro-cliente")
    assert amb.cliente.get("/v1/me/enderecos", headers=outro).json() == []
    assert amb.cliente.delete(f"/v1/me/enderecos/{a['id']}", headers=outro).status_code == 404
    r = amb.cliente.put(f"/v1/me/enderecos/{a['id']}", json=END, headers=outro)
    assert r.status_code == 404


def test_endereco_invalido_e_limite(amb):
    h = cab("t-cliente")
    assert (
        amb.cliente.post("/v1/me/enderecos", json={**END, "cep": "123"}, headers=h).status_code
        == 422
    )
    for _ in range(10):
        assert amb.cliente.post("/v1/me/enderecos", json=END, headers=h).status_code == 201
    assert amb.cliente.post("/v1/me/enderecos", json=END, headers=h).status_code == 409


def test_favoritos(amb):
    h = cab("t-cliente")
    assert amb.cliente.put("/v1/me/favoritos/pro-1", headers=h).status_code == 204
    assert amb.cliente.put("/v1/me/favoritos/pro-1", headers=h).status_code == 204  # idempotente
    assert [
        f["profissional_id"] for f in amb.cliente.get("/v1/me/favoritos", headers=h).json()
    ] == ["pro-1"]
    assert amb.cliente.get("/v1/me/favoritos", headers=cab("t-outro-cliente")).json() == []
    assert amb.cliente.delete("/v1/me/favoritos/pro-1", headers=h).status_code == 204
    assert amb.cliente.get("/v1/me/favoritos", headers=h).json() == []


def test_nao_favorita_a_si_mesmo(amb):
    assert amb.cliente.put("/v1/me/favoritos/cli-1", headers=cab("t-cliente")).status_code == 422


def test_contatos_de_confianca(amb):
    h = cab("t-cliente")
    r = amb.cliente.post(
        "/v1/me/contatos-confianca",
        json={"nome": "Maria", "telefone": "11 97777-6666", "parentesco": "Irmã"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    assert r.json()["telefone"] == "11977776666"
    cid = r.json()["id"]
    assert len(amb.cliente.get("/v1/me/contatos-confianca", headers=h).json()) == 1
    assert (
        amb.cliente.delete(
            f"/v1/me/contatos-confianca/{cid}", headers=cab("t-outro-cliente")
        ).status_code
        == 404
    )
    assert amb.cliente.delete(f"/v1/me/contatos-confianca/{cid}", headers=h).status_code == 204


def test_contatos_limite_de_cinco(amb):
    h = cab("t-cliente")
    corpo = {"nome": "Maria", "telefone": "11977776666"}
    for _ in range(5):
        assert (
            amb.cliente.post("/v1/me/contatos-confianca", json=corpo, headers=h).status_code == 201
        )
    assert amb.cliente.post("/v1/me/contatos-confianca", json=corpo, headers=h).status_code == 409
