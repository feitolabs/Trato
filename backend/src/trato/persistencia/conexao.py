"""Conexão com o Postgres (psycopg 3 + pool). A URL vem de DATABASE_URL, nunca do código.

Toda escrita roda em transação curta (`banco.transacao()`): abre, faz, confirma. Os gatilhos
adiados (conferência de total do orçamento e da nota) disparam no COMMIT, por isso o erro deles
também é capturado e traduzido aqui.
"""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout

from trato.persistencia.erros import ErroPersistencia, traduzir

# Conexão da transação em curso neste contexto (thread/requisição). Com ela aberta, `transacao()`
# reaproveita a mesma conexão: várias operações (ledger, disputa, pedido) viram UMA transação.
_EM_CURSO: ContextVar[psycopg.Connection[dict[str, Any]] | None] = ContextVar(
    "trato_transacao", default=None
)


class Banco:
    def __init__(
        self,
        dsn: str,
        *,
        papel: str = "service_role",
        tamanho_min: int = 1,
        tamanho_max: int = 5,
        timeout_instrucao_ms: int = 15_000,
        abrir: bool = True,
    ) -> None:
        """`papel`: papel do Postgres usado em cada transação (`set local role`), que é o que
        dá ao backend só os privilégios do `service_role`. Vazio = usar o usuário da conexão."""
        if papel and not papel.replace("_", "").isalnum():
            raise ValueError("Nome de papel inválido.")
        self._papel = papel
        self._pool = ConnectionPool(
            dsn,
            min_size=tamanho_min,
            max_size=tamanho_max,
            kwargs={
                "row_factory": dict_row,
                "options": f"-c statement_timeout={int(timeout_instrucao_ms)}",
                # Compatível com pooler em modo transação (Supabase, porta 6543).
                "prepare_threshold": None,
            },
            open=False,
        )
        if abrir:
            self.abrir()

    def abrir(self) -> None:
        self._pool.open()

    def fechar(self) -> None:
        self._pool.close()

    @contextmanager
    def transacao(self) -> Iterator[psycopg.Connection[dict[str, Any]]]:
        """Uma transação curta. Sai com COMMIT; qualquer erro desfaz tudo e vira erro de domínio.

        Aninhada (já há uma aberta neste contexto), reaproveita a conexão: quem confirma é a
        transação mais externa. Assim uma operação financeira inteira grava tudo ou nada.
        """
        atual = _EM_CURSO.get()
        if atual is not None:
            yield atual
            return
        try:
            with self._pool.connection() as con:
                if self._papel:
                    con.execute(f"set local role {self._papel}")
                marca = _EM_CURSO.set(con)
                try:
                    yield con
                finally:
                    _EM_CURSO.reset(marca)
        except psycopg.Error as erro:
            raise traduzir(erro) from erro
        except PoolTimeout as erro:
            raise ErroPersistencia("Banco de dados indisponível.") from erro
