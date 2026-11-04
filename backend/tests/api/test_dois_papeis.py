"""Profissional aprovado também contrata serviços: no pedido dele, age como cliente.

O que vale é a relação com o pedido, não o papel da conta. Antes, ele levava 403 ao abrir pedido,
não via os orçamentos recebidos e o chat abria uma conversa com ele mesmo.
"""

from __future__ import annotations

from conftest import CLIENTE, PROFISSIONAL, cab

from trato.api.repositorios import Orcamento
from trato.pedidos.estados import Estado

ITEM = {
    "tipo": "horas",
    "descricao": "Mão de obra",
    "quantidade": 1,
    "valor_unitario_centavos": 10_000,
}


def _meu_pedido(amb):
    amb.semear_pedido(
        Estado.ABERTO, cliente_id=PROFISSIONAL.id, profissional_id=None, orcamento_id=None
    )
    amb.contexto.orcamentos.adicionar(Orcamento("orc-2", "ped-1", "pro-2", 80_000))


def test_profissional_abre_pedido_como_cliente(amb):
    r = amb.cliente.post("/v1/pedidos", headers=cab("t-prof"))
    assert r.status_code == 201, r.text
    assert r.json()["cliente_id"] == PROFISSIONAL.id


def test_profissional_ve_todos_os_orcamentos_do_proprio_pedido(amb):
    _meu_pedido(amb)
    r = amb.cliente.get("/v1/pedidos/ped-1/orcamentos", headers=cab("t-prof"))
    assert r.status_code == 200
    assert {o["id"] for o in r.json()} >= {"orc-2"}


def test_profissional_nao_orca_o_proprio_pedido(amb):
    _meu_pedido(amb)
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/orcamentos", json={"itens": [ITEM]}, headers=cab("t-prof")
    )
    assert r.status_code == 403


def test_pedido_proprio_nao_aparece_entre_os_abertos(amb):
    _meu_pedido(amb)
    r = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-prof"))
    assert r.status_code == 200
    assert r.json() == []


def test_chat_do_proprio_pedido_nao_abre_conversa_consigo_mesmo(amb):
    _meu_pedido(amb)
    r = amb.cliente.get(
        "/v1/pedidos/ped-1/mensagens",
        params={"profissional_id": "pro-2"},
        headers=cab("t-prof"),
    )
    assert r.status_code == 200, r.text
    sem_alvo = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof"))
    assert sem_alvo.status_code == 422


def test_cliente_comum_continua_sem_ver_pedido_alheio(amb):
    amb.semear_pedido(
        Estado.ABERTO, cliente_id=PROFISSIONAL.id, profissional_id=None, orcamento_id=None
    )
    assert CLIENTE.id != PROFISSIONAL.id
    r = amb.cliente.get("/v1/pedidos/ped-1/orcamentos", headers=cab("t-cliente"))
    assert r.status_code == 404


def test_tipo_de_item_fora_do_banco_e_recusado_com_422(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/orcamentos",
        json={"itens": [{**ITEM, "tipo": "mao_de_obra"}]},
        headers=cab("t-prof"),
    )
    assert r.status_code == 422
