"""B32: nota_decimal opcional na avaliação (validação, gravação, média em memória)."""

from __future__ import annotations

import pytest
from conftest import CLIENTE, PROFISSIONAL, cab
from test_profissional_upload import _aprovar, e2  # noqa: F401

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.pedidos.estados import Estado as E


def _concluir_pedido(amb, pedido_id="ped-1"):
    amb.semear_pedido(E.CONCLUIDO, id=pedido_id)
    amb.contexto.usuarios.adicionar(PerfilDetalhe(CLIENTE.id, "Maria Silva", PapelUsuario.CLIENTE))
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(PROFISSIONAL.id, "Carlos Souza", PapelUsuario.PROFISSIONAL)
    )


def test_nota_decimal_valida_grava_e_media_em_memoria_usa_decimal(e2):  # noqa: F811
    _aprovar(e2)
    _concluir_pedido(e2.amb, "ped-1")
    r = e2.amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 5, "nota_decimal": 4.8},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["nota_geral"] == 5
    assert corpo["nota_decimal"] == 4.8

    salva = e2.amb.contexto.avaliacoes.obter("ped-1", "cliente_para_profissional")
    assert salva is not None and salva.nota_decimal == 4.8
    assert e2.amb.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 4.8

    perfil = e2.get(f"/v1/profissionais/{PROFISSIONAL.id}", "t-cliente")
    assert perfil.status_code == 200, perfil.text
    assert perfil.json()["nota_publica"] == 4.8
    assert perfil.json()["avaliacoes"][0]["nota_decimal"] == 4.8


def test_media_em_memoria_coalesce_decimal_e_legado_null(e2):  # noqa: F811
    _aprovar(e2)
    _concluir_pedido(e2.amb, "ped-1")
    e2.amb.semear_pedido(E.CONCLUIDO, id="ped-2")
    r1 = e2.amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 5, "nota_decimal": 4.8},
        headers=cab("t-cliente"),
    )
    r2 = e2.amb.cliente.post(
        "/v1/pedidos/ped-2/avaliacao",
        json={"nota_geral": 4},
        headers=cab("t-cliente"),
    )
    assert r1.status_code == 201 and r2.status_code == 201
    assert r2.json()["nota_decimal"] is None
    salva2 = e2.amb.contexto.avaliacoes.obter("ped-2", "cliente_para_profissional")
    assert salva2 is not None and salva2.nota_decimal is None
    # (4.8 + 4.0) / 2 = 4.4
    assert e2.amb.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 4.4
    perfil = e2.get(f"/v1/profissionais/{PROFISSIONAL.id}", "t-cliente")
    assert perfil.json()["nota_publica"] == 4.4


@pytest.mark.parametrize(
    "nota_geral,nota_decimal",
    [
        (5, 4.2),  # |4.2 - 5| = 0.8 > 0.5
        (3, 3.51),  # > 0.5 acima
        (3, 2.49),  # > 0.5 abaixo
        (5, 5.1),  # acima de 5
        (1, 0.9),  # abaixo de 1
        (4, 4.123),  # mais de 2 casas decimais
        (4, "4.2"),  # string não aceita
        (1, True),  # booleano não aceito
    ],
)
def test_nota_decimal_invalida_retorna_422(amb, nota_geral, nota_decimal):
    _concluir_pedido(amb, "ped-1")
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": nota_geral, "nota_decimal": nota_decimal},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 422, r.text


def test_nota_decimal_borda_meio_ponto_e_idempotencia(amb):
    _concluir_pedido(amb, "ped-1")
    r1 = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 5, "nota_decimal": 4.5},
        headers=cab("t-cliente"),
    )
    assert r1.status_code == 201, r1.text
    # Duplo toque com os mesmos dados devolve 200 idempotente
    r2 = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 5, "nota_decimal": 4.5},
        headers=cab("t-cliente"),
    )
    assert r2.status_code == 200 and r2.json()["nota_decimal"] == 4.5
    # Nota decimal diferente no mesmo pedido devolve 409
    r3 = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 5, "nota_decimal": 4.8},
        headers=cab("t-cliente"),
    )
    assert r3.status_code == 409


def test_profissional_avaliando_cliente_aceita_nota_decimal_opcional(amb):
    _concluir_pedido(amb, "ped-1")
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao",
        json={"nota_geral": 4, "nota_decimal": 4.25},
        headers=cab("t-prof"),
    )
    assert r.status_code == 201, r.text
    assert r.json()["nota_decimal"] == 4.25
