"""Cliente edita o pedido (descrição, valor pretendido, endereço) só enquanto aguarda orçamentos."""

from __future__ import annotations

from conftest import cab

CORPO = {
    "categoria_id": "c",
    "cidade_id": "x",
    "titulo": "Pintar sala",
    "descricao": "Pintar a sala de 20 m2",
    "faixa_preco_max_centavos": 50000,
    "endereco": {
        "logradouro": "Rua das Flores",
        "numero": "10",
        "bairro": "Centro",
        "cep": "35500-000",
    },
}


def _abrir(amb):
    r = amb.cliente.post("/v1/pedidos", json=CORPO, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_cliente_troca_valor_descricao_e_endereco(amb):
    pid = _abrir(amb)
    r = amb.cliente.patch(
        f"/v1/pedidos/{pid}",
        json={
            "descricao": "Pintar a sala e o corredor, uns 35 m2",
            "faixa_preco_max_centavos": 90000,
            "endereco": {"logradouro": "Rua das Flores", "numero": "10", "bairro": "Centro"},
        },
        headers=cab("t-cliente"),
    )
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["faixa_preco_max_centavos"] == 90000
    assert "35 m2" in corpo["descricao"]
    assert corpo["endereco"]["logradouro"] == "Rua das Flores"
    lido = amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-cliente")).json()
    assert lido["faixa_preco_max_centavos"] == 90000


def test_zero_limpa_a_faixa_e_minimo_nao_passa_do_maximo(amb):
    pid = _abrir(amb)
    r = amb.cliente.patch(
        f"/v1/pedidos/{pid}", json={"faixa_preco_max_centavos": 0}, headers=cab("t-cliente")
    )
    assert r.json()["faixa_preco_max_centavos"] is None
    r = amb.cliente.patch(
        f"/v1/pedidos/{pid}",
        json={"faixa_preco_min_centavos": 9000, "faixa_preco_max_centavos": 100},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 422


def test_telefone_na_descricao_continua_mascarado(amb):
    pid = _abrir(amb)
    r = amb.cliente.patch(
        f"/v1/pedidos/{pid}",
        json={"descricao": "Me chama no zap 31 97777-6666"},
        headers=cab("t-cliente"),
    )
    assert "97777" not in r.json()["descricao"]


def test_profissional_nao_edita_pedido_do_cliente(amb):
    pid = _abrir(amb)
    r = amb.cliente.patch(f"/v1/pedidos/{pid}", json={"urgente": True}, headers=cab("t-prof"))
    assert r.status_code in (403, 404)


def test_sem_login_e_401(amb):
    pid = _abrir(amb)
    assert amb.cliente.patch(f"/v1/pedidos/{pid}", json={"urgente": True}).status_code == 401
