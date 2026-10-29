"""Contexto injetável: tudo que as rotas usam e que muda entre teste e produção."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

from fastapi import Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from trato.api.auth import PapelUsuario, ProvedorAuth, Usuario
from trato.api.memoria_app import (
    AvaliacoesEmMemoria,
    ConversasEmMemoria,
    NotificacoesEmMemoria,
    UsuariosEmMemoria,
    VerificacoesEmMemoria,
)
from trato.api.repositorios import (
    EventoWebhook,
    ProvedorConfig,
    RepositorioContratos,
    RepositorioDisputas,
    RepositorioEventosWebhook,
    RepositorioGarantias,
    RepositorioLedger,
    RepositorioOrcamentos,
    RepositorioPedidos,
)
from trato.api.repositorios_app import (
    ProvedorTaxa,
    RepositorioAvaliacoes,
    RepositorioConversas,
    RepositorioNotificacoes,
    RepositorioUsuarios,
    RepositorioVerificacoes,
)
from trato.config import obter_config
from trato.pedidos.estados import Acao, Papel, Pedido


def agora_utc() -> datetime:
    return datetime.now(UTC)


def segredo_webhook_do_env() -> str:
    """O segredo do webhook vem do .env (STRIPE_WEBHOOK_SECRET), nunca do código."""
    return obter_config().stripe_webhook_secret.get_secret_value()


# Cada tipo de evento do Stripe ganha um manipulador que traduz o evento em ledger + transição
# do pedido. Os de pagamento vêm de `webhook_pagamento.py` (D13: "pago" só pelo webhook).
ManipuladorWebhook = Callable[[EventoWebhook, "Contexto"], None]
# Gancho após uma transição já gravada: (pedido antes, pedido depois, ação, contexto).
# Serve para efeitos financeiros que dependem da mudança (ex.: repartir a custódia ao concluir).
GanchoTransicao = Callable[[Pedido, Pedido, Acao, "Contexto"], None]


def _manipuladores_padrao() -> dict[str, ManipuladorWebhook]:
    from trato.api.webhook_pagamento import manipuladores_padrao

    return manipuladores_padrao()


@dataclass
class Contexto:
    auth: ProvedorAuth
    pedidos: RepositorioPedidos
    orcamentos: RepositorioOrcamentos
    contratos: RepositorioContratos
    ledger: RepositorioLedger
    disputas: RepositorioDisputas
    garantias: RepositorioGarantias
    eventos_webhook: RepositorioEventosWebhook
    config: ProvedorConfig
    agora: Callable[[], datetime] = agora_utc
    segredo_webhook: Callable[[], str] = segredo_webhook_do_env
    manipuladores_webhook: dict[str, ManipuladorWebhook] = field(
        default_factory=lambda: _manipuladores_padrao()
    )
    apos_transicao: list[GanchoTransicao] = field(default_factory=list)
    # Rotas do app. Em memória por padrão; a fábrica Postgres troca os que já têm tabela.
    conversas: RepositorioConversas = field(default_factory=ConversasEmMemoria)
    notificacoes: RepositorioNotificacoes = field(default_factory=NotificacoesEmMemoria)
    usuarios: RepositorioUsuarios = field(default_factory=UsuariosEmMemoria)
    verificacoes: RepositorioVerificacoes = field(default_factory=VerificacoesEmMemoria)
    avaliacoes: RepositorioAvaliacoes = field(default_factory=AvaliacoesEmMemoria)
    # Sem `taxa` ligada, o resumo do orçamento responde 503 (a taxa nunca vem do app).
    taxa: ProvedorTaxa | None = None
    # Só existem com persistência Postgres (a memória não os implementa).
    extras: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        # Antes da contratação a conversa mascara contatos: a memória pergunta ao repositório.
        if isinstance(self.conversas, ConversasEmMemoria) and self.conversas.contratado is None:
            self.conversas.contratado = lambda pid: self.contratos.obter_do_pedido(pid) is not None


def obter_contexto(request: Request) -> Contexto:
    contexto = getattr(request.app.state, "contexto", None)
    if contexto is None:
        raise HTTPException(503, "API ainda sem os repositórios ligados.")
    return contexto


_bearer = HTTPBearer(auto_error=False, description="Token do usuário (provedor de auth).")


def usuario_atual(
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    usuario = contexto.auth.autenticar(credenciais.credentials) if credenciais else None
    if usuario is None:
        raise HTTPException(
            401, "Faça login para continuar.", headers={"WWW-Authenticate": "Bearer"}
        )
    return usuario


def exigir_papel(*papeis: PapelUsuario) -> Callable[[Usuario], Usuario]:
    def dependencia(usuario: Usuario = Depends(usuario_atual)) -> Usuario:
        if usuario.papel not in papeis:
            raise HTTPException(403, "Seu perfil não pode fazer isso.")
        return usuario

    return dependencia


_PAPEL_DAS_REGRAS = {
    PapelUsuario.CLIENTE: Papel.CLIENTE,
    PapelUsuario.PROFISSIONAL: Papel.PROFISSIONAL,
    PapelUsuario.EQUIPE: Papel.MEDIADOR,
}


def papel_das_regras(usuario: Usuario) -> Papel:
    """Papel usado pela máquina de estados (a equipe age como mediador)."""
    return _PAPEL_DAS_REGRAS[usuario.papel]
