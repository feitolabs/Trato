"""Modalidade do serviço: presencial (endereço obrigatório) e remoto (só onde o admin liberou)."""

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta

import pytest
from conftest import AGORA, cab

from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Foto,
    Localizacao,
    Papel,
    Pedido,
    ProvaCheckIn,
    ProvaCheckOut,
    ProvaInvalida,
    transicionar,
)

ENDERECO = {"logradouro": "Rua das Flores", "numero": "10", "bairro": "Centro", "cep": "35500-000"}


def corpo(**extra):
    return {
        "categoria_id": "cat-ti",
        "cidade_id": "cid-bh",
        "titulo": "Montar o site",
        "descricao": "Preciso de um site simples.",
        **extra,
    }


def abrir(amb, **extra):
    return amb.cliente.post("/v1/pedidos", json=corpo(**extra), headers=cab("t-cliente"))


# --- criação do pedido ------------------------------------------------------------------------


def test_presencial_exige_endereco_completo(amb):
    sem = abrir(amb)
    assert sem.status_code == 422 and "endereço completo" in sem.json()["detail"]
    for faltando in ("logradouro", "numero", "bairro", "cep"):
        parcial = {k: v for k, v in ENDERECO.items() if k != faltando}
        if faltando == "logradouro":
            parcial["logradouro"] = " "
        r = abrir(amb, endereco=parcial)
        assert r.status_code == 422, faltando
    ok = abrir(amb, endereco=ENDERECO)
    assert ok.status_code == 201, ok.text
    assert ok.json()["modalidade"] == "presencial"


def test_remoto_so_em_categoria_que_o_admin_liberou(amb):
    recusado = abrir(amb, modalidade="remoto")
    assert recusado.status_code == 422 and "não atende de forma remota" in recusado.json()["detail"]
    amb.contexto.pedidos.categorias_remotas = {"cat-ti"}
    ok = abrir(amb, modalidade="remoto")  # sem endereço: não precisa
    assert ok.status_code == 201, ok.text
    assert ok.json()["modalidade"] == "remoto"
    visto = amb.cliente.get(f"/v1/pedidos/{ok.json()['id']}", headers=cab("t-cliente")).json()
    assert visto["modalidade"] == "remoto"


def test_categoria_remota_continua_aceitando_presencial_com_endereco(amb):
    amb.contexto.pedidos.categorias_remotas = {"cat-ti"}
    assert abrir(amb, modalidade="presencial").status_code == 422  # sem endereço
    assert abrir(amb, modalidade="presencial", endereco=ENDERECO).status_code == 201


def test_modalidade_invalida_e_recusada(amb):
    assert abrir(amb, modalidade="hibrido", endereco=ENDERECO).status_code == 422


# --- check-in e check-out ---------------------------------------------------------------------

PROF = Ator(Papel.PROFISSIONAL, "pro-1")
FOTO = Foto("f1", AGORA)


def agendado(remoto: bool) -> Pedido:
    return Pedido(
        id="p1",
        cliente_id="cli-1",
        aberto_em=AGORA - timedelta(days=1),
        estado=Estado.AGENDADO,
        profissional_id="pro-1",
        codigo_inicio="1234",
        remoto=remoto,
    )


def test_remoto_inicia_so_com_o_codigo_sem_foto_nem_localizacao():
    t = transicionar(
        agendado(True), Acao.FAZER_CHECK_IN, PROF, AGORA, ProvaCheckIn(codigo_inicio="1234"), None
    )
    assert t.pedido.estado is Estado.EM_ANDAMENTO


def test_remoto_ainda_confere_o_codigo():
    with pytest.raises(Exception, match="código"):
        transicionar(
            agendado(True),
            Acao.FAZER_CHECK_IN,
            PROF,
            AGORA,
            ProvaCheckIn(codigo_inicio="0000"),
            None,
        )


def test_presencial_continua_exigindo_foto_e_localizacao():
    with pytest.raises(ProvaInvalida):
        transicionar(
            agendado(False),
            Acao.FAZER_CHECK_IN,
            PROF,
            AGORA,
            ProvaCheckIn(codigo_inicio="1234"),
            None,
        )
    ok = transicionar(
        agendado(False),
        Acao.FAZER_CHECK_IN,
        PROF,
        AGORA,
        ProvaCheckIn(FOTO, Localizacao(-19.9, -43.9), "1234"),
        None,
    )
    assert ok.pedido.estado is Estado.EM_ANDAMENTO


def test_remoto_encerra_so_com_o_codigo_de_conclusao():
    em = replace(agendado(True), estado=Estado.EM_ANDAMENTO, codigo_conclusao="9876")
    t = transicionar(
        em, Acao.FAZER_CHECK_OUT, PROF, AGORA, ProvaCheckOut(codigo_conclusao="9876"), None
    )
    assert t.pedido.estado is Estado.EM_CONFIRMACAO
    presencial = replace(em, remoto=False)
    with pytest.raises(ProvaInvalida):
        transicionar(
            presencial,
            Acao.FAZER_CHECK_OUT,
            PROF,
            AGORA,
            ProvaCheckOut(codigo_conclusao="9876"),
            None,
        )
