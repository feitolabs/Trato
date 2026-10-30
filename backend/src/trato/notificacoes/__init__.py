"""Notificações, dispositivos de push, preferências e conversas (docs/backend-notificacoes.md)."""

from trato.notificacoes.eventos import Evento
from trato.notificacoes.rotas import ligar_ao_contexto, registrar_rotas
from trato.notificacoes.servico import ServicoNotificacoes

__all__ = ["Evento", "ServicoNotificacoes", "ligar_ao_contexto", "registrar_rotas"]
