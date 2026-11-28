"""BE-DISPUTA-INFO-84 (Termos 8.4): pedido de informação adicional em disputa (prazo mínimo 10 dias
úteis em Brasília + 22.3 na leitura), resposta pelo destinatário certo, encerramento sem resposta
após vencimento, notificação, auditoria e recuo 503 sem tabela."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

from conftest import CLIENTE
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.financeiro import periodo
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.persistencia.indisponibilidades import Janela as JanelaFalha

MSG = "Envie fotos adicionais do local e a nota do serviço realizado."


def _abrir_disputa(fluxo) -> str:
    pid = fluxo.ate_em_confirmacao()
    r = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/disputa",
        "t-cliente",
        {"motivo": "mal_feito", "descricao": "O acabamento ficou incompleto."},
    )
    assert r.status_code == 201, r.text
    return pid


def test_solicitar_prazo_10_dias_uteis_223_notificar_e_responder(fluxo):
    # Quinta 2026-11-12 10:00 Brasília (= 13:00 UTC); segunda 16/11 é feriado.
    # 10 dias úteis: 13(1), 17(2), 18(3), 19(4), 20(5), 23(6), 24(7), 25(8), 26(9), 27(10).
    pid = _abrir_disputa(fluxo)
    fluxo.amb.relogio.agora = datetime(2026, 11, 12, 13, 0, tzinfo=UTC)
    cfg = fluxo.ctx.config.carregar()
    cfg_fer = replace(cfg, disputas=replace(cfg.disputas, feriados=frozenset({date(2026, 11, 16)})))
    fluxo.ctx.config.carregar = lambda: cfg_fer

    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp()),
        ConfigNotificacoes(_env_file=None),
        fluxo.amb.relogio,
    )
    ligar_ao_contexto(fluxo.http.app, fluxo.ctx, notif)

    # Permissão: N1 pode listar (DISPUTAS_VER), mas não solicitar (DISPUTAS_DECIDIR)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/admin/disputas/{pid}/pedidos-informacao",
            "t-n1",
            {"destinatario_papel": "cliente", "mensagem": MSG},
        ).status_code
        == 403
    )
    assert (
        fluxo.chamar(
            "GET", f"/v1/admin/disputas/{pid}/pedidos-informacao", "t-mediador"
        ).status_code
        == 200
    )

    r = fluxo.chamar(
        "POST",
        f"/v1/admin/disputas/{pid}/pedidos-informacao",
        "t-mediador",
        {"destinatario_papel": "cliente", "mensagem": MSG},
    )
    assert r.status_code == 201, r.text
    info = r.json()
    esperado = datetime(2026, 11, 27, 23, 59, 59, tzinfo=periodo.BRASILIA)
    assert datetime.fromisoformat(info["responder_ate"]) == esperado
    assert info["status"] == "aguardando_resposta"

    # Notificação enviada ao cliente
    avisos = [
        n
        for n in notif.repo.listar(CLIENTE.id, False, 20)
        if n.tipo == Evento.DISPUTA_PEDIDO_INFORMACAO.value
    ]
    assert len(avisos) == 1 and "27/11/2026" in avisos[0].corpo

    # Prorrogação 22.3 (falha do app de 5h) aparece na leitura sem mudar o gravado
    fluxo.ctx.indisponibilidades.criar(
        JanelaFalha(
            id="f-84",
            origem="app",
            inicio_em=datetime(2026, 11, 13, 14, 0, tzinfo=UTC),
            fim_em=datetime(2026, 11, 13, 19, 0, tzinfo=UTC),
            motivo="Instabilidade no aplicativo",
            criada_por="eq-adm",
        )
    )
    lista_app = fluxo.chamar("GET", f"/v1/disputas/{pid}/pedidos-informacao", "t-cliente")
    assert lista_app.status_code == 200, lista_app.text
    assert "solicitante_id" not in lista_app.json()[0]
    assert datetime.fromisoformat(lista_app.json()[0]["responder_ate"]) == esperado + timedelta(
        hours=5
    )

    # Terceiro não-parte recebe 403
    assert (
        fluxo.chamar("GET", f"/v1/disputas/{pid}/pedidos-informacao", "t-outro-cliente").status_code
        == 403
    )

    # Outro papel (profissional) tentando responder pedido do cliente -> 403
    url_resp = f"/v1/disputas/{pid}/pedidos-informacao/{info['id']}/responder"
    assert (
        fluxo.chamar(
            "POST", url_resp, "t-prof", {"resposta_texto": "Tentativa indevida"}
        ).status_code
        == 403
    )

    # Cliente responde -> 200, status="respondido"
    r_resp = fluxo.chamar(
        "POST", url_resp, "t-cliente", {"resposta_texto": "Segue o esclarecimento completo."}
    )
    assert r_resp.status_code == 200, r_resp.text
    assert r_resp.json()["status"] == "respondido"
    assert r_resp.json()["resposta_texto"] == "Segue o esclarecimento completo."

    # Segunda resposta -> 409; encerrar sem resposta após respondido -> 409
    assert (
        fluxo.chamar(
            "POST", url_resp, "t-cliente", {"resposta_texto": "Segunda resposta"}
        ).status_code
        == 409
    )
    fluxo.amb.relogio.avancar(days=30)
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/admin/disputas/{pid}/pedidos-informacao/{info['id']}/encerrar-sem-resposta",
            "t-mediador",
            {"motivo": "Tentativa em pedido já respondido."},
        ).status_code
        == 409
    )


def test_encerrar_sem_resposta_so_apos_prazo_e_bloqueios_sem_tabela(fluxo):
    pid = _abrir_disputa(fluxo)
    fluxo.amb.relogio.agora = datetime(2026, 11, 2, 13, 0, tzinfo=UTC)

    r = fluxo.chamar(
        "POST",
        f"/v1/admin/disputas/{pid}/pedidos-informacao",
        "t-mediador",
        {"destinatario_papel": "profissional", "mensagem": MSG},
    )
    assert r.status_code == 201, r.text
    info = r.json()
    url_enc = f"/v1/admin/disputas/{pid}/pedidos-informacao/{info['id']}/encerrar-sem-resposta"

    # Antes de responder_ate -> 409
    assert (
        fluxo.chamar(
            "POST", url_enc, "t-mediador", {"motivo": "Tentativa antes de vencer o prazo."}
        ).status_code
        == 409
    )

    # Após responder_ate -> 200 + auditoria
    fluxo.amb.relogio.avancar(days=20)
    r_enc = fluxo.chamar(
        "POST", url_enc, "t-mediador", {"motivo": "Prazo de 10 dias úteis vencido sem retorno."}
    )
    assert r_enc.status_code == 200, r_enc.text
    assert r_enc.json()["status"] == "encerrado_sem_resposta"

    acoes = [e.acao for e in fluxo.amb.admin.auditoria.listar(FiltroAuditoria(), 100, 0)[0]]
    assert "disputa.pedido_informacao_solicitado" in acoes
    assert "disputa.pedido_informacao_encerrado_sem_resposta" in acoes

    # Responder após encerrado -> 409; encerrar de novo -> 409
    assert (
        fluxo.chamar(
            "POST",
            f"/v1/disputas/{pid}/pedidos-informacao/{info['id']}/responder",
            "t-prof",
            {"resposta_texto": "Resposta tardia"},
        ).status_code
        == 409
    )
    assert (
        fluxo.chamar(
            "POST", url_enc, "t-mediador", {"motivo": "Tentativa duplicada de encerramento."}
        ).status_code
        == 409
    )

    # Sem a tabela -> 503 sem quebrar o restante da disputa
    fluxo.ctx.disputa_pedidos_info.disponivel = lambda: False
    assert (
        fluxo.chamar(
            "GET", f"/v1/admin/disputas/{pid}/pedidos-informacao", "t-mediador"
        ).status_code
        == 503
    )
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}/disputa", "t-cliente").status_code == 200
