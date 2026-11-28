"""Pedidos de informação adicional em disputas (Termos 8.4; `disputa_pedidos_informacao`,
migration 20261128013000). Sem a tabela, `disponivel()` devolve False sem quebrar o restante."""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class PedidoInformacao:
    id: str
    disputa_id: str
    solicitante_id: str
    destinatario_papel: str
    mensagem: str
    solicitado_em: datetime
    responder_ate: datetime  # prazo original; prorrogação 22.3 é na leitura
    respondido_em: datetime | None = None
    resposta_texto: str | None = None
    encerrado_sem_resposta_em: datetime | None = None


class DisputaPedidosInfoEmMemoria:
    def __init__(self) -> None:
        self.disputas: Any = None
        self._itens: dict[str, PedidoInformacao] = {}
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def resolver_disputa(self, identificador: str) -> tuple[str, str] | None:
        if self.disputas is None:
            return None
        if self.disputas.obter(identificador) is None:
            return None
        return identificador, identificador

    def criar(
        self,
        disputa_id: str,
        solicitante_id: str,
        destinatario_papel: str,
        mensagem: str,
        solicitado_em: datetime,
        responder_ate: datetime,
    ) -> PedidoInformacao:
        with self._trava:
            novo = PedidoInformacao(
                id=str(uuid.uuid4()),
                disputa_id=disputa_id,
                solicitante_id=solicitante_id,
                destinatario_papel=destinatario_papel,
                mensagem=mensagem,
                solicitado_em=solicitado_em,
                responder_ate=responder_ate,
            )
            self._itens[novo.id] = novo
            return novo

    def obter(self, pedido_info_id: str) -> PedidoInformacao | None:
        return self._itens.get(pedido_info_id)

    def listar_da_disputa(self, disputa_id: str) -> list[PedidoInformacao]:
        with self._trava:
            itens = [x for x in self._itens.values() if x.disputa_id == disputa_id]
            itens.sort(key=lambda x: x.solicitado_em, reverse=True)
            return itens

    def responder(
        self, pedido_info_id: str, resposta_texto: str, respondido_em: datetime
    ) -> PedidoInformacao | None:
        with self._trava:
            atual = self._itens.get(pedido_info_id)
            if (
                atual is None
                or atual.respondido_em is not None
                or atual.encerrado_sem_resposta_em is not None
            ):
                return None
            self._itens[pedido_info_id] = replace(
                atual, respondido_em=respondido_em, resposta_texto=resposta_texto
            )
            return self._itens[pedido_info_id]

    def encerrar_sem_resposta(
        self, pedido_info_id: str, encerrado_em: datetime
    ) -> PedidoInformacao | None:
        with self._trava:
            atual = self._itens.get(pedido_info_id)
            if (
                atual is None
                or atual.respondido_em is not None
                or atual.encerrado_sem_resposta_em is not None
                or encerrado_em < atual.responder_ate
            ):
                return None
            self._itens[pedido_info_id] = replace(
                atual, encerrado_sem_resposta_em=encerrado_em
            )
            return self._itens[pedido_info_id]


_COLUNAS = (
    "id, disputa_id, solicitante_id, destinatario_papel, mensagem, solicitado_em, "
    "responder_ate, respondido_em, resposta_texto, encerrado_sem_resposta_em"
)


def _item(linha: Any) -> PedidoInformacao:
    return PedidoInformacao(
        **{
            **linha,
            "id": str(linha["id"]),
            "disputa_id": str(linha["disputa_id"]),
            "solicitante_id": str(linha["solicitante_id"]),
        }
    )


class DisputaPedidosInfoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _existe(con: Any) -> bool:
        return con.execute(
            "select to_regclass('public.disputa_pedidos_informacao') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._existe(con)

    def resolver_disputa(self, identificador: str) -> tuple[str, str] | None:
        uid = como_uuid(identificador)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select id, pedido_id from public.disputas "
                "where id = %s or pedido_id = %s order by aberta_em desc limit 1",
                (uid, uid),
            ).fetchone()
        if linha is None:
            return None
        return str(linha["id"]), str(linha["pedido_id"])

    def criar(
        self,
        disputa_id: str,
        solicitante_id: str,
        destinatario_papel: str,
        mensagem: str,
        solicitado_em: datetime,
        responder_ate: datetime,
    ) -> PedidoInformacao:
        did = como_uuid(disputa_id)
        sid = como_uuid(solicitante_id)
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.disputa_pedidos_informacao "
                "(disputa_id, solicitante_id, destinatario_papel, mensagem, "
                "solicitado_em, responder_ate) "
                f"values (%s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                (did, sid, destinatario_papel, mensagem, solicitado_em, responder_ate),
            ).fetchone()
        return _item(linha)

    def obter(self, pedido_info_id: str) -> PedidoInformacao | None:
        pid = como_uuid(pedido_info_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.disputa_pedidos_informacao where id = %s",
                (pid,),
            ).fetchone()
        return _item(linha) if linha else None

    def listar_da_disputa(self, disputa_id: str) -> list[PedidoInformacao]:
        did = como_uuid(disputa_id)
        if did is None:
            return []
        with self._banco.transacao() as con:
            if not self._existe(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from public.disputa_pedidos_informacao "
                "where disputa_id = %s order by solicitado_em desc",
                (did,),
            ).fetchall()
        return [_item(x) for x in linhas]

    def responder(
        self, pedido_info_id: str, resposta_texto: str, respondido_em: datetime
    ) -> PedidoInformacao | None:
        pid = como_uuid(pedido_info_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.disputa_pedidos_informacao "
                "set respondido_em = %s, resposta_texto = %s "
                "where id = %s and respondido_em is null and encerrado_sem_resposta_em is null "
                f"returning {_COLUNAS}",
                (respondido_em, resposta_texto, pid),
            ).fetchone()
        return _item(linha) if linha else None

    def encerrar_sem_resposta(
        self, pedido_info_id: str, encerrado_em: datetime
    ) -> PedidoInformacao | None:
        pid = como_uuid(pedido_info_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.disputa_pedidos_informacao "
                "set encerrado_sem_resposta_em = %s "
                "where id = %s and respondido_em is null and encerrado_sem_resposta_em is null "
                f"returning {_COLUNAS}",
                (encerrado_em, pid),
            ).fetchone()
        return _item(linha) if linha else None
