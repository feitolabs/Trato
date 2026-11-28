"""BE-TERMOS-96-52 (9.6): com o contato bloqueado, telefone e endereço já enviados deixam de
aparecer na conversa e na lista de conversas, e voltam quando o incidente é encerrado."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from test_ausencia_cliente import pedido_marcado
from test_cautela_rotas import encerrar, incidente
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes

TELEFONE = "98765-4321"
TEXTO = f"Meu numero e (11) {TELEFONE}"


def ligar(f) -> None:
    ligar_ao_contexto(
        f.amb.cliente.app,
        f.ctx,
        ServicoNotificacoes(
            RepositorioEmMemoria(),
            Canais(CanalApp()),
            ConfigNotificacoes(_env_file=None),
            f.amb.relogio,
        ),
    )


def textos(f, conversa) -> str:
    return " ".join(m.texto for m in f.ctx.conversas.listar(conversa))


def ultima(f, quem) -> str:
    r = f.chamar("GET", "/v1/conversas", quem)
    assert r.status_code == 200, r.text
    return " ".join(c["ultima_mensagem"] or "" for c in r.json())


def test_telefone_ja_enviado_some_com_o_contato_bloqueado_e_volta(fluxo):
    ligar(fluxo)
    pid, _ = pedido_marcado(fluxo)
    pedido = fluxo.ctx.pedidos.obter(pid)
    conversa = fluxo.ctx.conversas.abrir(pid, pedido.profissional_id)
    fluxo.ctx.conversas.enviar(conversa, pedido.cliente_id, TEXTO)
    for quem in ("t-prof", "t-cliente"):
        assert TELEFONE in ultima(fluxo, quem)
    assert TELEFONE in textos(fluxo, conversa)

    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    assert TELEFONE not in textos(fluxo, conversa)
    for quem in ("t-prof", "t-cliente"):
        assert TELEFONE not in ultima(fluxo, quem)
    # O original continua guardado como prova (leitura auditada do painel).
    assert TELEFONE in " ".join(fluxo.ctx.conversas.originais(conversa).values())

    encerrar(fluxo.ctx, iid)
    assert TELEFONE in textos(fluxo, conversa)


def test_lista_de_conversas_esconde_o_contato_de_pedido_cancelado(fluxo):
    ligar(fluxo)
    pid, _ = pedido_marcado(fluxo)
    pedido = fluxo.ctx.pedidos.obter(pid)
    conversa = fluxo.ctx.conversas.abrir(pid, pedido.profissional_id)
    fluxo.ctx.conversas.enviar(conversa, pedido.cliente_id, TEXTO)
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Mudança de planos."})
    assert r.status_code == 200, r.text
    assert TELEFONE not in textos(fluxo, conversa)
    assert TELEFONE not in ultima(fluxo, "t-prof")
