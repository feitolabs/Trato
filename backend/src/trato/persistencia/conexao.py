"""Conexão com o Postgres (psycopg 3 + pool). A URL vem de DATABASE_URL, nunca do código.

Toda escrita roda em transação curta (`banco.transacao()`): abre, faz, confirma. Os gatilhos
adiados (conferência de total do orçamento e da nota) disparam no COMMIT, por isso o erro deles
também é capturado e traduzido aqui.
"""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass
from typing import Any

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool, PoolTimeout

from trato.persistencia.erros import ErroPersistencia, traduzir


@dataclass
class MedicaoConsultas:
    """Quantas consultas e quanto tempo de banco uma requisição gastou (medidor de performance)."""

    consultas: int = 0
    segundos: float = 0.0


# Medição da requisição em curso. Nulo = ninguém está medindo (custo zero).
MEDICAO: ContextVar[MedicaoConsultas | None] = ContextVar("trato_medicao", default=None)


class _CursorMedido(psycopg.Cursor[Any]):
    """Cursor que soma consultas e tempo na medição em curso, se houver."""

    def execute(self, *args: Any, **kwargs: Any) -> Any:
        medicao = MEDICAO.get()
        if medicao is None:
            return super().execute(*args, **kwargs)
        inicio = time.perf_counter()
        try:
            return super().execute(*args, **kwargs)
        finally:
            medicao.consultas += 1
            medicao.segundos += time.perf_counter() - inicio


def _pooler_em_modo_transacao(dsn: str) -> bool:
    """Porta 6543 do Supabase = pooler em modo transação: estado de sessão não sobrevive."""
    return ":6543" in dsn


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
        tamanho_min: int = 2,
        tamanho_max: int = 5,
        timeout_instrucao_ms: int = 15_000,
        abrir: bool = True,
    ) -> None:
        """`papel`: papel do Postgres que dá ao backend só os privilégios do `service_role`.
        Vazio = usar o usuário da conexão.

        Performance: com conexão de sessão (porta 5432 ou Postgres direto) o papel é fixado uma
        vez, quando o pool abre a conexão física. Isso evita uma ida e volta ao banco em toda
        transação. No pooler em modo transação (6543) continua `set local role` por transação.
        `tamanho_min` mantém conexões já abertas para o primeiro acesso não pagar a abertura."""
        if papel and not papel.replace("_", "").isalnum():
            raise ValueError("Nome de papel inválido.")
        self._papel_por_transacao = papel if _pooler_em_modo_transacao(dsn) else ""
        papel_sessao = "" if self._papel_por_transacao else papel

        def configurar(con: psycopg.Connection[Any]) -> None:
            if papel_sessao:
                con.execute(f"set role {papel_sessao}")
                con.commit()

        self._pool = ConnectionPool(
            dsn,
            min_size=tamanho_min,
            max_size=tamanho_max,
            configure=configurar,
            kwargs={
                "row_factory": dict_row,
                "cursor_factory": _CursorMedido,
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
                if self._papel_por_transacao:
                    con.execute(f"set local role {self._papel_por_transacao}")
                marca = _EM_CURSO.set(con)
                try:
                    yield con
                finally:
                    _EM_CURSO.reset(marca)
        except psycopg.Error as erro:
            raise traduzir(erro) from erro
        except PoolTimeout as erro:
            raise ErroPersistencia("Banco de dados indisponível.") from erro
