"""Avisos (notificações) disparados por rotas do app: mensagem nova e orçamento recebido.

Aviso é secundário: se falhar, a ação que o gerou (mensagem, orçamento) já está gravada e segue.
O texto da mensagem nunca vai na notificação (pode ter dado pessoal).
"""

from __future__ import annotations

import logging

from fastapi import Request

from trato.api.contexto import Contexto
from trato.notificacoes.eventos import Evento

log = logging.getLogger("trato.notificacoes")


def servicos_de_notificacao(request: Request, contexto: Contexto):  # type: ignore[no-untyped-def]
    """(ServicoNotificacoes, ServicoMensagens) deste app (montados uma vez)."""
    from trato.notificacoes.rotas import _servicos  # import tardio: evita ciclo

    return _servicos(request, contexto)


def avisar_mensagem_nova(
    request: Request,
    contexto: Contexto,
    *,
    conversa_id: str,
    pedido_id: str,
    autor_id: str,
    destinatario_id: str,
    mensagem_id: int,
) -> None:
    """Avisa quem recebeu. Várias mensagens seguidas, ainda sem leitura, geram um aviso só."""
    try:
        anteriores = list(contexto.conversas.listar(conversa_id))
        if len(anteriores) >= 2:
            anterior = anteriores[-2]
            if anterior.autor_id == autor_id and anterior.lida_em is None:
                return
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.MENSAGEM_NOVA,
            destinatario_id,
            chave=f"{conversa_id}:{mensagem_id}",
            pedido_id=pedido_id,
            dados={
                "conversa_id": conversa_id,
                "profissional_id": _profissional(contexto, pedido_id, autor_id, destinatario_id),
            },
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de mensagem nova falhou")


def _profissional(contexto: Contexto, pedido_id: str, autor_id: str, destinatario_id: str) -> str:
    """Quem é o profissional da conversa (o cliente precisa dele para abrir o chat certo)."""
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is not None and autor_id == pedido.cliente_id:
        return destinatario_id
    return autor_id


def avisar_orcamento_recebido(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    cliente_id: str,
    orcamento_id: str,
) -> None:
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.ORCAMENTO_RECEBIDO, cliente_id, chave=orcamento_id, pedido_id=pedido_id
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de orçamento recebido falhou")
