"""Liga as transições de pedido às notificações (`Contexto.apos_transicao`).

Só ações que têm evento próprio entram aqui. O resto (orçamento recebido, disputa respondida,
avaliação, aditivo, lembretes) chama `ServicoNotificacoes.notificar` direto de onde acontece.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

from trato.notificacoes.eventos import Evento
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Acao, Pedido

log = logging.getLogger("trato.notificacoes")

# ação -> (evento, para quem: "cliente" | "profissional" | "ambos")
MAPA: dict[Acao, tuple[Evento, str]] = {
    Acao.ACEITAR_ORCAMENTO: (Evento.ORCAMENTO_ACEITO, "profissional"),
    Acao.CONFIRMAR_PAGAMENTO: (Evento.PAGAMENTO_CONFIRMADO, "ambos"),
    Acao.CONFIRMAR_AGENDA: (Evento.CODIGO_INICIO, "cliente"),
    Acao.FAZER_CHECK_OUT: (Evento.CONCLUSAO_PARA_CONFIRMAR, "cliente"),
    Acao.ABRIR_DISPUTA: (Evento.DISPUTA_ABERTA, "ambos"),
    Acao.ENCERRAR_DISPUTA_POR_ACORDO: (Evento.DISPUTA_DECIDIDA, "ambos"),
    Acao.DECIDIR_DISPUTA: (Evento.DISPUTA_DECIDIDA, "ambos"),
    Acao.PEDIR_RETRABALHO: (Evento.RETRABALHO, "profissional"),
}


def destinatarios(pedido: Pedido, quem: str) -> list[str]:
    ids = []
    if quem in ("cliente", "ambos"):
        ids.append(pedido.cliente_id)
    if quem in ("profissional", "ambos") and pedido.profissional_id:
        ids.append(pedido.profissional_id)
    return ids


def criar_gancho(servico: ServicoNotificacoes) -> Callable[[Pedido, Pedido, Acao, Any], None]:
    """Gancho `(antes, depois, acao, contexto)` que notifica. Nunca derruba a transição."""

    def gancho(antes: Pedido, depois: Pedido, acao: Acao, _contexto: Any) -> None:
        alvo = MAPA.get(acao)
        if alvo is None:
            return
        evento, quem = alvo
        for usuario in destinatarios(depois, quem):
            try:
                servico.notificar(
                    evento, usuario, chave=f"{depois.id}:{acao.value}", pedido_id=depois.id
                )
            except Exception:  # noqa: BLE001 - aviso é secundário; a transição já foi gravada
                log.exception("Notificação do evento %s falhou", evento.value)

    return gancho
