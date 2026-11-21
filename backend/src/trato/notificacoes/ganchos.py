"""Liga as transições de pedido às notificações (`Contexto.apos_transicao`).

Quem recebe, o título e o corpo de cada ação estão em `textos.planejar`. O resto (orçamento
recebido, disputa respondida, avaliação, aditivo, nota de material, lembretes) chama
`ServicoNotificacoes.notificar` direto de onde acontece (`api/avisos.py`).
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

from trato.notificacoes.eventos import Evento
from trato.notificacoes.servico import ServicoNotificacoes
from trato.notificacoes.textos import SIMPLES, planejar
from trato.pedidos.estados import Acao, Pedido

log = logging.getLogger("trato.notificacoes")

# ação -> (evento, para quem). Mantido para quem consulta o mapa; o texto vem de `planejar`.
MAPA: dict[Acao, tuple[Evento, str]] = {
    **SIMPLES,
    Acao.CONFIRMAR_PAGAMENTO: (Evento.PAGAMENTO_CONFIRMADO, "ambos"),
    Acao.CONFIRMAR_AGENDA: (Evento.CODIGO_INICIO, "cliente"),
    Acao.FAZER_CHECK_IN: (Evento.SERVICO_INICIADO, "cliente"),
    Acao.FAZER_CHECK_OUT: (Evento.CONCLUSAO_PARA_CONFIRMAR, "cliente"),
    Acao.CONFIRMAR_CONCLUSAO: (Evento.CLIENTE_CONFIRMOU, "profissional"),
    Acao.PEDIR_RETRABALHO: (Evento.RETRABALHO, "profissional"),
    Acao.RESOLVER_RETRABALHO: (Evento.RETRABALHO_RESOLVIDO, "cliente"),
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

    def gancho(antes: Pedido, depois: Pedido, acao: Acao, contexto: Any) -> None:
        if acao not in MAPA:
            return
        try:
            avisos = planejar(acao, depois, contexto)
        except Exception:  # noqa: BLE001 - aviso é secundário; a transição já foi gravada
            log.exception("Planejar notificação da ação %s falhou", acao.value)
            return
        for aviso in avisos:
            try:
                servico.notificar(
                    aviso.evento,
                    aviso.usuario_id,
                    chave=aviso.chave,
                    pedido_id=depois.id,
                    corpo=aviso.corpo,
                    titulo=aviso.titulo,
                )
            except Exception:  # noqa: BLE001 - aviso é secundário; a transição já foi gravada
                log.exception("Notificação do evento %s falhou", aviso.evento.value)

    return gancho
