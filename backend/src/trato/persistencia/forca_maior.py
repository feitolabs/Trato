"""Eventos externos / força maior (Termos 7.8 e 22.6; `eventos_forca_maior`, migration
20261128020000). Sem a tabela, `disponivel()` devolve False sem quebrar outras rotas."""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class EventoForcaMaior:
    id: str
    pedido_id: str
    solicitante_id: str
    solicitante_papel: str
    acao_solicitada: str
    descricao: str
    comprovantes: tuple[str, ...] = ()
    status: str = "pendente"
    criado_em: datetime | None = None
    analista_id: str | None = None
    justificativa_decisao: str | None = None
    decidido_em: datetime | None = None
    chave_idempotencia: str | None = None


class ForcaMaiorEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, EventoForcaMaior] = {}
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def criar(
        self,
        pedido_id: str,
        solicitante_id: str,
        solicitante_papel: str,
        acao_solicitada: str,
        descricao: str,
        comprovantes: Sequence[str],
        criado_em: datetime,
    ) -> EventoForcaMaior:
        with self._trava:
            novo = EventoForcaMaior(
                id=str(uuid.uuid4()),
                pedido_id=pedido_id,
                solicitante_id=solicitante_id,
                solicitante_papel=solicitante_papel,
                acao_solicitada=acao_solicitada,
                descricao=descricao,
                comprovantes=tuple(comprovantes),
                status="pendente",
                criado_em=criado_em,
            )
            self._itens[novo.id] = novo
            return novo

    def obter(self, evento_id: str) -> EventoForcaMaior | None:
        return self._itens.get(evento_id)

    def obter_por_chave(self, chave_idempotencia: str) -> EventoForcaMaior | None:
        with self._trava:
            return next(
                (x for x in self._itens.values() if x.chave_idempotencia == chave_idempotencia),
                None,
            )

    def listar_do_pedido(self, pedido_id: str) -> list[EventoForcaMaior]:
        with self._trava:
            itens = [x for x in self._itens.values() if x.pedido_id == pedido_id]
            itens.sort(
                key=lambda x: x.criado_em.timestamp() if x.criado_em else 0.0,
                reverse=True,
            )
            return itens

    def listar(
        self, status: str | None, limite: int, deslocamento: int
    ) -> tuple[list[EventoForcaMaior], int]:
        with self._trava:
            itens = [x for x in self._itens.values() if status is None or x.status == status]
            itens.sort(
                key=lambda x: x.criado_em.timestamp() if x.criado_em else 0.0,
                reverse=(status != "pendente"),
            )
            return itens[deslocamento : deslocamento + limite], len(itens)

    def decidir(
        self,
        evento_id: str,
        status: str,
        analista_id: str,
        justificativa_decisao: str,
        decidido_em: datetime,
        chave_idempotencia: str,
    ) -> EventoForcaMaior | None:
        with self._trava:
            atual = self._itens.get(evento_id)
            if atual is None or atual.status != "pendente":
                return None
            if any(x.chave_idempotencia == chave_idempotencia for x in self._itens.values()):
                return None
            self._itens[evento_id] = replace(
                atual,
                status=status,
                analista_id=analista_id,
                justificativa_decisao=justificativa_decisao,
                decidido_em=decidido_em,
                chave_idempotencia=chave_idempotencia,
            )
            return self._itens[evento_id]


_COLUNAS = (
    "id, pedido_id, solicitante_id, solicitante_papel, acao_solicitada, descricao, "
    "comprovantes, status, criado_em, analista_id, justificativa_decisao, decidido_em, "
    "chave_idempotencia"
)


def _item(linha: Any) -> EventoForcaMaior:
    return EventoForcaMaior(
        id=str(linha["id"]),
        pedido_id=str(linha["pedido_id"]),
        solicitante_id=str(linha["solicitante_id"]),
        solicitante_papel=linha["solicitante_papel"],
        acao_solicitada=linha["acao_solicitada"],
        descricao=linha["descricao"],
        comprovantes=tuple(linha["comprovantes"] or ()),
        status=linha["status"],
        criado_em=linha["criado_em"],
        analista_id=str(linha["analista_id"]) if linha.get("analista_id") else None,
        justificativa_decisao=linha.get("justificativa_decisao"),
        decidido_em=linha.get("decidido_em"),
        chave_idempotencia=linha.get("chave_idempotencia"),
    )


class ForcaMaiorPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _existe(con: Any) -> bool:
        return con.execute(
            "select to_regclass('public.eventos_forca_maior') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._existe(con)

    def criar(
        self,
        pedido_id: str,
        solicitante_id: str,
        solicitante_papel: str,
        acao_solicitada: str,
        descricao: str,
        comprovantes: Sequence[str],
        criado_em: datetime,
    ) -> EventoForcaMaior:
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.eventos_forca_maior "
                "(pedido_id, solicitante_id, solicitante_papel, acao_solicitada, "
                "descricao, comprovantes, criado_em) "
                f"values (%s, %s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                (
                    como_uuid(pedido_id),
                    como_uuid(solicitante_id),
                    solicitante_papel,
                    acao_solicitada,
                    descricao,
                    list(comprovantes),
                    criado_em,
                ),
            ).fetchone()
        return _item(linha)

    def obter(self, evento_id: str) -> EventoForcaMaior | None:
        eid = como_uuid(evento_id)
        if eid is None:
            return None
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.eventos_forca_maior where id = %s", (eid,)
            ).fetchone()
        return _item(linha) if linha else None

    def obter_por_chave(self, chave_idempotencia: str) -> EventoForcaMaior | None:
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.eventos_forca_maior "
                "where chave_idempotencia = %s",
                (chave_idempotencia,),
            ).fetchone()
        return _item(linha) if linha else None

    def listar_do_pedido(self, pedido_id: str) -> list[EventoForcaMaior]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return []
        with self._banco.transacao() as con:
            if not self._existe(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from public.eventos_forca_maior "
                "where pedido_id = %s order by criado_em desc",
                (pid,),
            ).fetchall()
        return [_item(x) for x in linhas]

    def listar(
        self, status: str | None, limite: int, deslocamento: int
    ) -> tuple[list[EventoForcaMaior], int]:
        with self._banco.transacao() as con:
            if not self._existe(con):
                return [], 0
            if status is not None:
                ordem = "criado_em asc" if status == "pendente" else "criado_em desc"
                total = con.execute(
                    "select count(*)::int as n from public.eventos_forca_maior where status = %s",
                    (status,),
                ).fetchone()["n"]
                linhas = con.execute(
                    f"select {_COLUNAS} from public.eventos_forca_maior "
                    f"where status = %s order by {ordem} limit %s offset %s",
                    (status, limite, deslocamento),
                ).fetchall()
            else:
                total = con.execute(
                    "select count(*)::int as n from public.eventos_forca_maior"
                ).fetchone()["n"]
                linhas = con.execute(
                    f"select {_COLUNAS} from public.eventos_forca_maior "
                    "order by criado_em desc limit %s offset %s",
                    (limite, deslocamento),
                ).fetchall()
        return [_item(x) for x in linhas], int(total)

    def decidir(
        self,
        evento_id: str,
        status: str,
        analista_id: str,
        justificativa_decisao: str,
        decidido_em: datetime,
        chave_idempotencia: str,
    ) -> EventoForcaMaior | None:
        eid = como_uuid(evento_id)
        aid = como_uuid(analista_id)
        if eid is None or aid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.eventos_forca_maior "
                "set status = %s, analista_id = %s, justificativa_decisao = %s, "
                "decidido_em = %s, chave_idempotencia = %s "
                "where id = %s and status = 'pendente' "
                f"returning {_COLUNAS}",
                (status, aid, justificativa_decisao, decidido_em, chave_idempotencia, eid),
            ).fetchone()
        return _item(linha) if linha else None
