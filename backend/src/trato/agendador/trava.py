"""Trava para o agendador não rodar em duplicado.

`TravaEmMemoria` vale dentro de UM processo (testes, instância única). `TravaAdvisoryPostgres`
vale entre processos e máquinas: usa `pg_try_advisory_lock` numa conexão dedicada, que o Postgres
solta sozinho se o processo morrer. As duas são "tente e, se ocupada, desista" (nunca esperam).
"""

from __future__ import annotations

import hashlib
import threading
from collections.abc import Iterator
from contextlib import AbstractContextManager, contextmanager
from typing import Protocol

import psycopg


class Trava(Protocol):
    def adquirir(self, nome: str) -> AbstractContextManager[bool]:
        """Entra com True se conseguiu a trava, False se outra instância está rodando."""


class TravaEmMemoria:
    _ocupadas: set[str] = set()  # compartilhado no processo: duas instâncias veem a mesma
    _guarda = threading.Lock()

    @contextmanager
    def adquirir(self, nome: str) -> Iterator[bool]:
        with self._guarda:
            livre = nome not in self._ocupadas
            if livre:
                self._ocupadas.add(nome)
        try:
            yield livre
        finally:
            if livre:
                with self._guarda:
                    self._ocupadas.discard(nome)


def chave_advisory(nome: str) -> int:
    """bigint estável (o mesmo em todas as máquinas) para o nome da trava."""
    return int.from_bytes(
        hashlib.blake2b(nome.encode(), digest_size=8).digest(), "big", signed=True
    )


class TravaAdvisoryPostgres:
    def __init__(self, dsn: str) -> None:
        self._dsn = dsn

    @contextmanager
    def adquirir(self, nome: str) -> Iterator[bool]:
        # Conexão própria e autocommit: a trava vive na sessão, não numa transação.
        with psycopg.connect(self._dsn, autocommit=True) as con:
            chave = chave_advisory(nome)
            livre = bool(con.execute("select pg_try_advisory_lock(%s)", (chave,)).fetchone()[0])
            try:
                yield livre
            finally:
                if livre:
                    con.execute("select pg_advisory_unlock(%s)", (chave,))
