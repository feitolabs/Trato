"""Registro de eventos processados: o mesmo evento não roda duas vezes (tarefa F4.5b).

Fluxo: ``iniciar`` reserva a chave de forma atômica; se deu certo, processa; ao final
``concluir``. Se o processamento falhar, ``liberar`` devolve a chave para o reenvio do
provedor tentar de novo. A implementação do banco (futura) usa ``unique(provedor, evento_id)``
da tabela ``eventos_webhook``; a chave aqui é o texto ``"<provedor>:<evento_id>"``.
"""

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import Protocol, TypeVar

T = TypeVar("T")


class RegistroEventos(Protocol):
    def iniciar(self, chave: str) -> bool:
        """Reserva a chave. ``False`` se já foi reservada ou processada."""

    def concluir(self, chave: str) -> None:
        """Marca como processada de vez."""

    def liberar(self, chave: str) -> None:
        """Desfaz a reserva (processamento falhou), permitindo nova tentativa."""


class RegistroEventosEmMemoria:
    """Implementação para teste e desenvolvimento. Segura entre threads."""

    def __init__(self) -> None:
        self._trava = threading.Lock()
        self._em_processamento: set[str] = set()
        self._processadas: set[str] = set()

    def iniciar(self, chave: str) -> bool:
        if not chave:
            raise ValueError("chave de idempotência vazia")
        with self._trava:
            if chave in self._processadas or chave in self._em_processamento:
                return False
            self._em_processamento.add(chave)
            return True

    def concluir(self, chave: str) -> None:
        with self._trava:
            self._em_processamento.discard(chave)
            self._processadas.add(chave)

    def liberar(self, chave: str) -> None:
        with self._trava:
            self._em_processamento.discard(chave)

    def foi_processada(self, chave: str) -> bool:
        with self._trava:
            return chave in self._processadas


def processar_uma_vez(
    registro: RegistroEventos, chave: str, acao: Callable[[], T]
) -> tuple[bool, T | None]:
    """Roda ``acao`` só se a chave é nova. Devolve ``(executou, resultado)``."""
    if not registro.iniciar(chave):
        return False, None
    try:
        resultado = acao()
    except BaseException:
        registro.liberar(chave)
        raise
    registro.concluir(chave)
    return True, resultado
