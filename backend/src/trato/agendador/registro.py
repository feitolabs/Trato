"""Registro de ações de rotina já executadas (idempotência por chave).

A chave vem de `trato.rotinas.regras.AcaoRotina.chave` e é estável. O Postgres usa a tabela
`agendador_execucoes` (migration 20261029040000, ainda não aplicada no banco real).
"""

from __future__ import annotations

from datetime import datetime
from typing import Protocol

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


class RegistroExecucoes(Protocol):
    def ja_executadas(self) -> frozenset[str]: ...

    def marcar(self, chave: str, tipo: str, pedido_id: str, agora: datetime) -> bool:
        """True se esta chamada foi a primeira a marcar; False se a chave já existia."""


class RegistroEmMemoria:
    def __init__(self) -> None:
        self._chaves: set[str] = set()

    def ja_executadas(self) -> frozenset[str]:
        return frozenset(self._chaves)

    def marcar(self, chave: str, tipo: str, pedido_id: str, agora: datetime) -> bool:
        if chave in self._chaves:
            return False
        self._chaves.add(chave)
        return True


class RegistroPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def ja_executadas(self) -> frozenset[str]:
        with self._banco.transacao() as con:
            linhas = con.execute("select chave from public.agendador_execucoes").fetchall()
        return frozenset(l["chave"] for l in linhas)  # noqa: E741

    def marcar(self, chave: str, tipo: str, pedido_id: str, agora: datetime) -> bool:
        with self._banco.transacao() as con:
            nova = con.execute(
                "insert into public.agendador_execucoes (chave, tipo, pedido_id, executada_em) "
                "values (%s, %s, %s, %s) on conflict (chave) do nothing returning chave",
                (chave, tipo, como_uuid(pedido_id), agora),
            ).fetchone()
        return nova is not None
