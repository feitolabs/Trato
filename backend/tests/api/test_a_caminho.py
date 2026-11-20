"""B7: aviso "a caminho" do profissional ao cliente (idempotente em 10 minutos)."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, CLIENTE, cab

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import Janela

URL = "/v1/profissional/pedidos/ped-1/a-caminho"


def _montar(amb, estado=E.AGENDADO):
    amb.semear_pedido(estado, janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)))
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp()),
        ConfigNotificacoes(_env_file=None),
        amb.relogio,
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    return notif


def _avisos(notif):
    return [n for n in notif.repo.listar(CLIENTE.id, False, 50) if n.tipo == Evento.A_CAMINHO.value]


def test_a_caminho_avisa_o_cliente_com_a_estimativa(amb):
    notif = _montar(amb)
    r = amb.cliente.post(URL, json={"eta_minutos": 20}, headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json() == {"pedido_id": "ped-1", "enviado": True, "eta_minutos": 20}
    [aviso] = _avisos(notif)
    assert aviso.titulo == "Seu profissional está a caminho"
    assert "~20 min" in aviso.corpo and aviso.dados["pedido_id"] == "ped-1"


def test_a_caminho_sem_corpo_funciona_e_nao_cita_estimativa(amb):
    notif = _montar(amb)
    r = amb.cliente.post(URL, headers=cab("t-prof"))
    assert r.status_code == 200 and r.json()["enviado"] is True
    assert "Chega em" not in _avisos(notif)[0].corpo


def test_a_caminho_so_o_profissional_dono_do_pedido(amb):
    notif = _montar(amb)
    assert amb.cliente.post(URL, headers=cab("t-outro-prof")).status_code == 404
    assert amb.cliente.post(URL, headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.post(URL).status_code == 401
    assert _avisos(notif) == []


def test_a_caminho_em_estado_errado_da_409(amb):
    notif = _montar(amb, E.CONCLUIDO)
    r = amb.cliente.post(URL, headers=cab("t-prof"))
    assert r.status_code == 409 and "agendado" in r.json()["detail"]
    assert _avisos(notif) == []


def test_a_caminho_valida_a_estimativa(amb):
    _montar(amb)
    for eta in (4, 181, "10"):
        r = amb.cliente.post(URL, json={"eta_minutos": eta}, headers=cab("t-prof"))
        assert r.status_code == 422


def test_a_caminho_e_idempotente_por_10_minutos(amb):
    notif = _montar(amb)
    assert amb.cliente.post(URL, headers=cab("t-prof")).json()["enviado"] is True
    amb.relogio.avancar(minutes=9)
    r = amb.cliente.post(URL, headers=cab("t-prof"))
    assert r.status_code == 200 and r.json()["enviado"] is False
    assert len(_avisos(notif)) == 1
    amb.relogio.avancar(minutes=2)
    assert amb.cliente.post(URL, headers=cab("t-prof")).json()["enviado"] is True
    assert len(_avisos(notif)) == 2
