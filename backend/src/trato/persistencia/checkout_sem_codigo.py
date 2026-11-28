"""Casos de Check-out sem o Código Final (Termos 5.7; `checkout_sem_codigo_casos`, migrations
20261127230000 e 20261128010000). Sem a tabela, tudo vira "não há caso"."""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any

from trato.pedidos.estados import Acao, Estado
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class Caso:
    id: str
    pedido_id: str
    check_out_em: datetime
    criado_em: datetime | None = None
    contatado_em: datetime | None = None
    canal: str | None = None
    responder_ate: datetime | None = None  # original; a prorrogação 22.3 é na leitura
    respondido_em: datetime | None = None
    resposta: str | None = None
    analista_id: str | None = None
    decisao: str | None = None
    justificativa: str | None = None
    decidido_em: datetime | None = None
    chave_idempotencia: str | None = None


class CheckoutSemCodigoEmMemoria:
    """Quem liga diz onde estão os pedidos (para `vigente`, como a função do banco)."""

    def __init__(self) -> None:
        self.pedidos: Any = None
        self._itens: dict[str, Caso] = {}
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def fase2_disponivel(self) -> bool:
        return True

    def vigente(self, pedido_id: str) -> datetime | None:
        """O check-out sem código que vale agora. Retrabalho resolvido não é caso."""
        pedido = self.pedidos.obter(pedido_id) if self.pedidos is not None else None
        if pedido is None or pedido.estado is not Estado.EM_CONFIRMACAO:
            return None
        saidas = [
            e
            for e in self.pedidos.eventos(pedido_id)
            if e.acao in (Acao.FAZER_CHECK_OUT, Acao.RESOLVER_RETRABALHO)
        ]
        if not saidas or saidas[-1].acao is not Acao.FAZER_CHECK_OUT:
            return None
        return saidas[-1].em if getattr(saidas[-1].prova, "sem_codigo", False) else None

    def abrir(self, pedido_id: str, check_out_em: datetime, agora: datetime) -> Caso:
        with self._trava:
            for item in self._itens.values():
                if (item.pedido_id, item.check_out_em) == (pedido_id, check_out_em):
                    return item
            novo = Caso(str(uuid.uuid4()), pedido_id, check_out_em, agora)
            self._itens[novo.id] = novo
            return novo

    def obter(self, caso_id: str) -> Caso | None:
        return self._itens.get(caso_id)

    def obter_por_chave(self, chave_idempotencia: str) -> Caso | None:
        with self._trava:
            return next(
                (c for c in self._itens.values() if c.chave_idempotencia == chave_idempotencia),
                None,
            )

    def em_aberto(self) -> list[Caso]:
        with self._trava:
            return [
                c
                for c in self._itens.values()
                if c.respondido_em is None and c.decidido_em is None
            ]

    def registrar_contato(
        self, caso_id: str, em: datetime, canal: str, responder_ate: datetime
    ) -> Caso | None:
        """Só o primeiro contato vale. `None`: já havia contato, resposta ou decisão."""
        with self._trava:
            atual = self._itens.get(caso_id)
            if atual is None or atual.contatado_em or atual.respondido_em or atual.decidido_em:
                return None
            self._itens[caso_id] = replace(
                atual, contatado_em=em, canal=canal, responder_ate=responder_ate
            )
            return self._itens[caso_id]

    def responder(self, pedido_id: str, resposta: str, em: datetime) -> int:
        with self._trava:
            abertos = [c for c in self.em_aberto() if c.pedido_id == pedido_id]
            for item in abertos:
                self._itens[item.id] = replace(item, respondido_em=em, resposta=resposta)
            return len(abertos)

    def decidir(
        self,
        caso_id: str,
        analista_id: str,
        decisao: str,
        justificativa: str,
        decidido_em: datetime,
        chave_idempotencia: str,
    ) -> Caso | None:
        with self._trava:
            atual = self._itens.get(caso_id)
            if atual is None or atual.respondido_em is not None or atual.decidido_em is not None:
                return None
            if any(c.chave_idempotencia == chave_idempotencia for c in self._itens.values()):
                return None
            self._itens[caso_id] = replace(
                atual,
                analista_id=analista_id,
                decisao=decisao,
                justificativa=justificativa,
                decidido_em=decidido_em,
                chave_idempotencia=chave_idempotencia,
            )
            return self._itens[caso_id]


_COLUNAS = (
    "id, pedido_id, check_out_em, criado_em, contatado_em, canal, responder_ate, "
    "respondido_em, resposta, analista_id, decisao, justificativa, decidido_em, "
    "to_jsonb(checkout_sem_codigo_casos) ->> 'chave_idempotencia' as chave_idempotencia"
)


def _caso(linha: Any) -> Caso:
    return Caso(
        **{
            **linha,
            "id": str(linha["id"]),
            "pedido_id": str(linha["pedido_id"]),
            "analista_id": str(linha["analista_id"]) if linha.get("analista_id") else None,
        }
    )


class CheckoutSemCodigoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _existe(con: Any) -> bool:
        # Consulta que não falha sem a tabela: um erro abortaria a transação de fora.
        return con.execute(
            "select to_regclass('public.checkout_sem_codigo_casos') is not null as tem"
        ).fetchone()["tem"]

    @staticmethod
    def _fase2(con: Any) -> bool:
        return con.execute(
            "select exists ("
            "select 1 from information_schema.columns "
            "where table_schema = 'public' and table_name = 'checkout_sem_codigo_casos' "
            "and column_name = 'chave_idempotencia'"
            ") as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._existe(con)

    def fase2_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._existe(con) and self._fase2(con)

    def vigente(self, pedido_id: str) -> datetime | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            return con.execute(
                "select public.checkout_sem_codigo_vigente(%s) as em", (pid,)
            ).fetchone()["em"]

    def abrir(self, pedido_id: str, check_out_em: datetime, agora: datetime) -> Caso:
        pid = como_uuid(pedido_id)
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.checkout_sem_codigo_casos (pedido_id, check_out_em) "
                "values (%s, %s) on conflict (pedido_id, check_out_em) do nothing",
                (pid, check_out_em),
            )
            linha = con.execute(
                f"select {_COLUNAS} from public.checkout_sem_codigo_casos "
                "where pedido_id = %s and check_out_em = %s",
                (pid, check_out_em),
            ).fetchone()
        return _caso(linha)

    def obter(self, caso_id: str) -> Caso | None:
        cid = como_uuid(caso_id)
        if cid is None:
            return None
        with self._banco.transacao() as con:
            if not self._existe(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.checkout_sem_codigo_casos where id = %s", (cid,)
            ).fetchone()
        return _caso(linha) if linha else None

    def obter_por_chave(self, chave_idempotencia: str) -> Caso | None:
        with self._banco.transacao() as con:
            if not self._existe(con) or not self._fase2(con):
                return None
            linha = con.execute(
                f"select {_COLUNAS} from public.checkout_sem_codigo_casos "
                "where chave_idempotencia = %s",
                (chave_idempotencia,),
            ).fetchone()
        return _caso(linha) if linha else None

    def em_aberto(self) -> list[Caso]:
        with self._banco.transacao() as con:
            if not self._existe(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from public.checkout_sem_codigo_casos "
                "where respondido_em is null and decidido_em is null order by criado_em"
            ).fetchall()
        return [_caso(x) for x in linhas]

    def registrar_contato(
        self, caso_id: str, em: datetime, canal: str, responder_ate: datetime
    ) -> Caso | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.checkout_sem_codigo_casos set contatado_em = %s, canal = %s, "
                "responder_ate = %s where id = %s and contatado_em is null "
                f"and respondido_em is null and decidido_em is null returning {_COLUNAS}",
                (em, canal, responder_ate, como_uuid(caso_id)),
            ).fetchone()
        return _caso(linha) if linha else None

    def responder(self, pedido_id: str, resposta: str, em: datetime) -> int:
        pid = como_uuid(pedido_id)
        if pid is None:
            return 0
        with self._banco.transacao() as con:
            if not self._existe(con):
                return 0
            return con.execute(
                "update public.checkout_sem_codigo_casos set respondido_em = %s, resposta = %s "
                "where pedido_id = %s and respondido_em is null and decidido_em is null",
                (em, resposta, pid),
            ).rowcount

    def decidir(
        self,
        caso_id: str,
        analista_id: str,
        decisao: str,
        justificativa: str,
        decidido_em: datetime,
        chave_idempotencia: str,
    ) -> Caso | None:
        cid = como_uuid(caso_id)
        aid = como_uuid(analista_id)
        if cid is None or aid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.checkout_sem_codigo_casos "
                "set analista_id = %s, decisao = %s, justificativa = %s, "
                "decidido_em = %s, chave_idempotencia = %s "
                "where id = %s and respondido_em is null and decidido_em is null "
                f"returning {_COLUNAS}",
                (aid, decisao, justificativa, decidido_em, chave_idempotencia, cid),
            ).fetchone()
        return _caso(linha) if linha else None
