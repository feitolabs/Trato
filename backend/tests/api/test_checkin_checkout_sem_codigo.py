"""B5: Plano B no check-in e check-out sem código do cliente (sem liberar repasse sem aceite)."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_memoria
from trato.agendador.registro import RegistroEmMemoria
from trato.agendador.trava import TravaEmMemoria
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import Janela
from trato.rotinas.regras import ConfigRotinas


def _foto(amb, arquivo_id="foto-1"):
    return {"arquivo_id": arquivo_id, "tirada_em": amb.relogio.agora.isoformat()}


def _loc():
    return {"latitude": -23.5505, "longitude": -46.6333}


def _semear_agendado(amb, pid="ped-1"):
    amb.semear_pedido(
        E.AGENDADO,
        id=pid,
        janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)),
        codigo_inicio="1234",
        codigo_conclusao="5678",
    )
    amb.semear_dinheiro(cobrado=100_000, taxa=0)


def _montar_agendador(amb):
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp()),
        ConfigNotificacoes(_env_file=None),
        amb.relogio,
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    agendador = Agendador(
        FonteContexto(
            amb.contexto,
            ids_ativos_memoria(amb.contexto),
            ConfigRotinas(prazo_liberacao=timedelta(days=7)),
        ),
        ExecutorContexto(amb.contexto, notif),
        RegistroEmMemoria(),
        TravaEmMemoria(),
        amb.relogio,
        notif,
    )
    return agendador, notif


# --- Check-in sem código -------------------------------------------------------------------------


def test_check_in_sem_codigo_exige_justificativa_foto_e_gps(amb):
    _semear_agendado(amb)
    # Sem justificativa -> 422
    r_sem_just = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_in",
        json={"prova": {"foto": _foto(amb), "localizacao": _loc(), "sem_codigo": True}},
        headers=cab("t-prof"),
    )
    assert r_sem_just.status_code == 422

    # Sem foto/GPS -> 422
    r_sem_gps = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_in",
        json={"prova": {"foto": _foto(amb), "sem_codigo": True, "justificativa": "Sem sinal"}},
        headers=cab("t-prof"),
    )
    assert r_sem_gps.status_code == 422


def test_check_in_sem_codigo_transiciona_e_notifica_cliente(amb):
    _semear_agendado(amb)
    _, notif = _montar_agendador(amb)
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_in",
        json={
            "prova": {
                "foto": _foto(amb),
                "localizacao": _loc(),
                "sem_codigo": True,
                "justificativa": "Cliente pediu para iniciar com o porteiro.",
            }
        },
        headers=cab("t-prof"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "em_andamento"
    eventos = amb.cliente.get("/v1/pedidos/ped-1/eventos", headers=cab("t-prof")).json()
    assert eventos[-1]["acao"] == "fazer_check_in"
    notas = [
        n
        for n in notif.repo.listar(CLIENTE.id, False, 10)
        if n.tipo == Evento.CHECK_IN_SEM_CODIGO.value
    ]
    assert len(notas) == 1


# --- Check-out sem código ------------------------------------------------------------------------


def test_check_out_sem_codigo_exige_justificativa_foto_e_gps(amb):
    _semear_agendado(amb)
    amb.semear_pedido(
        E.EM_ANDAMENTO,
        id="ped-1",
        check_in_em=AGORA,
        codigo_inicio="1234",
        codigo_conclusao="5678",
    )
    # Sem justificativa -> 422
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_out",
            json={"prova": {"foto_final": _foto(amb), "localizacao": _loc(), "sem_codigo": True}},
            headers=cab("t-prof"),
        ).status_code
        == 422
    )
    # Sem GPS -> 422
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_out",
            json={
                "prova": {
                    "foto_final": _foto(amb),
                    "sem_codigo": True,
                    "justificativa": "Cliente saiu antes do término.",
                }
            },
            headers=cab("t-prof"),
        ).status_code
        == 422
    )


def test_check_out_sem_codigo_nao_libera_dinheiro_antes_da_confirmacao_do_cliente(amb):
    _semear_agendado(amb)
    agendador, _ = _montar_agendador(amb)

    # Check-in normal com código
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_in",
            json={"prova": {"foto": _foto(amb), "localizacao": _loc(), "codigo_inicio": "1234"}},
            headers=cab("t-prof"),
        ).status_code
        == 200
    )

    # Check-out sem código
    r_out = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_out",
        json={
            "prova": {
                "foto_final": _foto(amb, "foto-2"),
                "localizacao": _loc(),
                "sem_codigo": True,
                "justificativa": "Cliente precisou sair e pediu para finalizar.",
            }
        },
        headers=cab("t-prof"),
    )
    assert r_out.status_code == 200, r_out.text
    corpo = r_out.json()
    assert corpo["estado"] == "em_confirmacao"
    assert corpo["check_out_sem_codigo"] is True

    # Mesmo após passar o prazo de confirmação (7 dias) + liberação (7 dias), NÃO conclui nem
    # libera o repasse automaticamente!
    amb.relogio.avancar(days=20)
    res_ciclo = agendador.rodar_uma_vez()
    assert res_ciclo.executadas == 0
    assert amb.contexto.pedidos.obter("ped-1").estado is E.EM_CONFIRMACAO
    saldos_antes = amb.contexto.ledger.saldos_pedido("ped-1", PROFISSIONAL.id)
    assert saldos_antes.a_liberar == 100_000 and saldos_antes.liberado == 0

    # Cliente confirma explicitamente a conclusão -> conclui e abre garantia; depois libera no ciclo.
    r_conf = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/confirmar_conclusao",
        headers=cab("t-cliente"),
    )
    assert r_conf.status_code == 200, r_conf.text
    assert r_conf.json()["estado"] == "concluido"
    assert amb.contexto.garantias.obter_garantia("ped-1") is not None

    amb.relogio.avancar(days=8)
    agendador.rodar_uma_vez()
    saldos_depois = amb.contexto.ledger.saldos_pedido("ped-1", PROFISSIONAL.id)
    assert saldos_depois.a_liberar == 0 and saldos_depois.liberado == 100_000


def test_check_out_sem_codigo_mantem_disputa_disponivel(amb):
    _semear_agendado(amb)
    amb.semear_pedido(
        E.EM_ANDAMENTO,
        id="ped-1",
        check_in_em=AGORA,
        codigo_inicio="1234",
        codigo_conclusao="5678",
    )
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_out",
            json={
                "prova": {
                    "foto_final": _foto(amb),
                    "localizacao": _loc(),
                    "sem_codigo": True,
                    "justificativa": "Sem código",
                }
            },
            headers=cab("t-prof"),
        ).status_code
        == 200
    )
    r_disp = amb.cliente.post(
        "/v1/pedidos/ped-1/disputa",
        json={"motivo": "mal_feito", "descricao": "Não foi finalizado corretamente."},
        headers=cab("t-cliente"),
    )
    assert r_disp.status_code == 201, r_disp.text
    assert amb.contexto.pedidos.obter("ped-1").estado is E.EM_DISPUTA


# --- Fluxo normal com código continua idêntico ---------------------------------------------------


def test_check_in_e_out_normal_com_codigo_continua_identico(amb):
    _semear_agendado(amb)
    agendador, _ = _montar_agendador(amb)
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-1/acoes/fazer_check_in",
            json={"prova": {"foto": _foto(amb), "localizacao": _loc(), "codigo_inicio": "1234"}},
            headers=cab("t-prof"),
        ).status_code
        == 200
    )
    codigo_fim = amb.contexto.pedidos.obter("ped-1").codigo_conclusao
    r_out = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_out",
        json={"prova": {"foto_final": _foto(amb), "codigo_conclusao": codigo_fim}},
        headers=cab("t-prof"),
    )
    assert r_out.status_code == 200
    assert r_out.json()["check_out_sem_codigo"] is False

    # No fluxo normal com código, conclusão por prazo continua funcionando.
    amb.relogio.avancar(days=8)
    assert agendador.rodar_uma_vez().executadas == 1
    assert amb.contexto.pedidos.obter("ped-1").estado is E.CONCLUIDO
