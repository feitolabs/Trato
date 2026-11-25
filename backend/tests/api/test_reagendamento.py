"""Reagendamento: propor, listar, aceitar e recusar nova janela dentro do pedido."""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, cab

from trato.pedidos.estados import Estado, Janela

URL = "/v1/pedidos/ped-1/reagendamentos"
H = timedelta(hours=1)


def _corpo(inicio_h: int = 48, motivo: str = "Imprevisto no trabalho"):
    ini = AGORA + inicio_h * H
    return {
        "nova_janela_inicio": ini.isoformat(),
        "nova_janela_fim": (ini + 2 * H).isoformat(),
        "motivo": motivo,
    }


def _agendado(amb):
    amb.semear_pedido(Estado.AGENDADO, janela=Janela(AGORA + 24 * H, AGORA + 26 * H))


def _propor(amb, quem="t-cliente", **kw):
    return amb.cliente.post(URL, json=_corpo(**kw), headers=cab(quem))


def test_fluxo_feliz_cliente_propoe_profissional_aceita_e_janela_muda(amb):
    _agendado(amb)
    r = _propor(amb)
    assert r.status_code == 201, r.text
    proposta = r.json()
    assert proposta["status"] == "pendente" and proposta["motivo"] == "Imprevisto no trabalho"

    lista = amb.cliente.get(URL, headers=cab("t-prof")).json()
    assert [i["id"] for i in lista] == [proposta["id"]]

    ok = amb.cliente.post(f"{URL}/{proposta['id']}/aceitar", headers=cab("t-prof"))
    assert ok.status_code == 200, ok.text
    corpo = ok.json()
    assert corpo["status"] == "aceito" and corpo["respondido_por"] == "pro-1"
    assert corpo["respondido_em"] is not None
    janela = amb.contexto.pedidos.obter("ped-1").janela
    assert janela.inicio == AGORA + 48 * H and janela.fim == AGORA + 50 * H


def test_pago_e_retido_aceitar_confirma_a_agenda(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    pid = _propor(amb).json()["id"]
    assert amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-prof")).status_code == 200
    pedido = amb.contexto.pedidos.obter("ped-1")
    assert pedido.estado is Estado.AGENDADO and pedido.janela.inicio == AGORA + 48 * H


def test_quem_propos_nao_aceita_a_propria_proposta(amb):
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    r = amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-cliente"))
    assert r.status_code == 403
    assert r.json()["detail"] == "Apenas a outra parte pode aceitar o reagendamento."


def test_segunda_proposta_pendente_da_409(amb):
    _agendado(amb)
    assert _propor(amb).status_code == 201
    r = _propor(amb, quem="t-prof", inicio_h=72)
    assert r.status_code == 409
    assert r.json()["detail"] == "Já existe um pedido de reagendamento aguardando resposta."


def test_depois_de_recusar_pode_propor_de_novo(amb):
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    rec = amb.cliente.post(f"{URL}/{pid}/recusar", headers=cab("t-prof"))
    assert rec.status_code == 200 and rec.json()["status"] == "recusado"
    assert amb.contexto.pedidos.obter("ped-1").janela.inicio == AGORA + 24 * H  # nada mudou
    assert _propor(amb, quem="t-prof", inicio_h=72).status_code == 201
    assert [i["status"] for i in amb.cliente.get(URL, headers=cab("t-cliente")).json()] == [
        "pendente",
        "recusado",
    ]  # mais recentes primeiro


def test_quem_propos_pode_cancelar(amb):
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    r = amb.cliente.post(f"{URL}/{pid}/recusar", headers=cab("t-cliente"))
    assert r.json()["status"] == "cancelado"


def test_resposta_so_vale_uma_vez(amb):
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    assert amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-prof")).status_code == 200
    assert amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-prof")).status_code == 409
    assert amb.cliente.post(f"{URL}/{pid}/recusar", headers=cab("t-prof")).status_code == 409


def test_terceiro_recebe_404_e_sem_login_401(amb):
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    for token in ("t-outro-cliente", "t-outro-prof"):
        assert amb.cliente.get(URL, headers=cab(token)).status_code == 404
        assert _propor(amb, quem=token).status_code == 404
        assert amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab(token)).status_code == 404
    assert amb.cliente.get(URL).status_code == 401


@pytest.mark.parametrize("estado", [Estado.ABERTO, Estado.EM_ANDAMENTO, Estado.CONCLUIDO])
def test_estado_invalido_da_409(amb, estado):
    amb.semear_pedido(estado)
    r = _propor(amb)
    assert r.status_code == 409
    assert r.json()["detail"] == "Este pedido não pode ser reagendado no momento."


def test_janela_invalida_da_422(amb):
    _agendado(amb)
    passado = {
        "nova_janela_inicio": (AGORA - H).isoformat(),
        "nova_janela_fim": (AGORA + H).isoformat(),
    }
    invertida = {
        "nova_janela_inicio": (AGORA + 5 * H).isoformat(),
        "nova_janela_fim": (AGORA + 4 * H).isoformat(),
    }
    for corpo in (passado, invertida):
        assert amb.cliente.post(URL, json=corpo, headers=cab("t-cliente")).status_code == 422


def test_outra_parte_e_avisada_ao_propor_e_ao_responder(amb):
    from trato.notificacoes import ligar_ao_contexto
    from trato.notificacoes.canais import Canais, CanalApp
    from trato.notificacoes.config import ConfigNotificacoes
    from trato.notificacoes.repositorio import RepositorioEmMemoria
    from trato.notificacoes.servico import ServicoNotificacoes

    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    amb.cliente.app.state.notificador = notif
    _agendado(amb)
    pid = _propor(amb).json()["id"]
    assert [n.tipo for n in repo.listar("pro-1", False, 10)] == ["agenda.reagendamento_proposto"]
    amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-prof"))
    # quem propôs é avisado da resposta e, como cliente, do novo código de início
    assert sorted(n.tipo for n in repo.listar("cli-1", False, 10)) == [
        "agenda.codigo_inicio",
        "agenda.reagendamento_respondido",
    ]


def _com_notificacoes(amb):
    from trato.notificacoes import ligar_ao_contexto
    from trato.notificacoes.canais import Canais, CanalApp
    from trato.notificacoes.config import ConfigNotificacoes
    from trato.notificacoes.repositorio import RepositorioEmMemoria
    from trato.notificacoes.servico import ServicoNotificacoes

    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    amb.cliente.app.state.notificador = notif
    return repo


def test_aceite_remarca_regera_o_codigo_e_avisa_as_duas_pontas(amb):
    repo = _com_notificacoes(amb)
    amb.semear_pedido(
        Estado.AGENDADO, janela=Janela(AGORA + 24 * H, AGORA + 26 * H), codigo_inicio="1234"
    )
    pid = amb.cliente.post(URL, json=_corpo(), headers=cab("t-prof")).json()["id"]  # prof propõe
    antes = amb.contexto.pedidos.obter("ped-1")
    assert antes.janela == Janela(AGORA + 24 * H, AGORA + 26 * H)  # proposta não muda nada
    assert antes.codigo_inicio == "1234"

    r = amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    depois = amb.contexto.pedidos.obter("ped-1")
    assert depois.janela == Janela(AGORA + 48 * H, AGORA + 50 * H)
    assert depois.codigo_inicio not in ("", "1234")  # novo código só por este fluxo
    # quem propôs (profissional) é avisado da resposta; o cliente, do novo código
    assert [n.tipo for n in repo.listar("pro-1", False, 10)] == ["agenda.reagendamento_respondido"]
    novos = [n for n in repo.listar("cli-1", False, 10) if n.tipo == "agenda.codigo_inicio"]
    assert len(novos) == 1 and "novo código" in (novos[0].corpo or "").lower()
    assert "1234" not in (novos[0].corpo or "") and depois.codigo_inicio not in (
        novos[0].corpo or ""
    )


def test_aceite_pela_parte_errada_nao_remarca(amb):
    amb.semear_pedido(
        Estado.AGENDADO, janela=Janela(AGORA + 24 * H, AGORA + 26 * H), codigo_inicio="1234"
    )
    pid = _propor(amb, "t-cliente").json()["id"]
    antes = amb.contexto.pedidos.obter("ped-1")
    # o próprio autor da proposta não aceita
    assert amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab("t-cliente")).status_code == 403
    # terceiro (outro profissional/cliente) não vê nem aceita
    for quem in ("t-outro-prof", "t-outro-cliente"):
        r = amb.cliente.post(f"{URL}/{pid}/aceitar", headers=cab(quem))
        assert r.status_code in (403, 404), (quem, r.status_code)
    depois = amb.contexto.pedidos.obter("ped-1")
    assert depois.janela == antes.janela and depois.codigo_inicio == "1234"
