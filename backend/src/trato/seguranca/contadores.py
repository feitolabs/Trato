"""Contadores de janela deslizante e bloqueios temporários, em memória.

Vale para UM processo. Com mais de uma instância da API, trocar por um armazenamento
compartilhado (Redis ou o próprio Postgres) mantendo esta interface: ver
`docs/backend-seguranca.md`.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from collections.abc import Callable


class Contadores:
    def __init__(self, relogio: Callable[[], float] = time.time, retencao_s: float = 172_800):
        self.agora = relogio
        self._retencao = retencao_s
        self._eventos: dict[str, deque[float]] = {}
        self._bloqueios: dict[str, float] = {}
        self._trava = threading.Lock()
        self._operacoes = 0

    def _podar(self, chave: str, agora: float) -> deque[float]:
        fila = self._eventos.setdefault(chave, deque())
        while fila and fila[0] < agora - self._retencao:
            fila.popleft()
        return fila

    def adicionar(self, chave: str) -> None:
        with self._trava:
            agora = self.agora()
            self._podar(chave, agora).append(agora)
            self._operacoes += 1
            if self._operacoes % 2000 == 0:
                self._limpar(agora)

    def quantos(self, chave: str, janela_s: float) -> int:
        with self._trava:
            agora = self.agora()
            return sum(1 for t in self._podar(chave, agora) if t > agora - janela_s)

    def segundos_ate_liberar(self, chave: str, janela_s: float, maximo: int) -> int:
        """Quanto falta para a janela ter espaço de novo (o evento mais antigo sai)."""
        with self._trava:
            agora = self.agora()
            na_janela = [t for t in self._podar(chave, agora) if t > agora - janela_s]
            if len(na_janela) < maximo:
                return 0
            sair = na_janela[len(na_janela) - maximo]
            return max(1, int(sair + janela_s - agora) + 1)

    def ultimo(self, chave: str) -> float | None:
        with self._trava:
            fila = self._podar(chave, self.agora())
            return fila[-1] if fila else None

    def bloquear(self, chave: str, segundos: float) -> bool:
        """Bloqueia a chave; devolve verdadeiro se o bloqueio é novo (para abrir flag uma vez)."""
        with self._trava:
            agora = self.agora()
            novo = self._bloqueios.get(chave, 0) <= agora
            self._bloqueios[chave] = max(self._bloqueios.get(chave, 0), agora + segundos)
            return novo

    def bloqueado_por(self, chave: str) -> int:
        with self._trava:
            falta = self._bloqueios.get(chave, 0) - self.agora()
            return int(falta) + 1 if falta > 0 else 0

    def _limpar(self, agora: float) -> None:
        for chave in [c for c, f in self._eventos.items() if not f]:
            del self._eventos[chave]
        for chave in [c for c, ate in self._bloqueios.items() if ate <= agora]:
            del self._bloqueios[chave]
