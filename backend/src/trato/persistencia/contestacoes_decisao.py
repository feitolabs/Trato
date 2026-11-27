"""Contestação da decisão de disputa (Termos 8.7; tabela `disputa_contestacoes`).

Não confundir com `persistencia/contestacoes.py` (contestação de cartão). O registro não move
dinheiro nem muda a disputa. Sem a tabela, `disponivel()` é falso e as rotas respondem 503.
"""

from __future__ import annotations

import threading
import uuid
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco

ABERTA = "aberta"
EM_ANALISE = "em_analise"
AGUARDANDO_APROVACAO = "aguardando_aprovacao"
PENDENTES = (ABERTA, EM_ANALISE, AGUARDANDO_APROVACAO)
FINAIS = ("mantida", "alterada", "revertida")


@dataclass(frozen=True)
class ContestacaoDecisao:
    disputa_id: str
    pedido_id: str
    contestante_id: str
    o_que_faltou: str
    canal: str  # app | sac
    aberta_em: datetime
    contestar_ate: datetime
    responder_ate: datetime
    anexos: tuple[str, ...] = ()
    status: str = ABERTA
    analista_id: str | None = None
    resposta: str | None = None
    nova_decisao: str | None = None
    novo_valor_reembolso_centavos: int | None = None
    aprovada_por: str | None = None
    decidida_em: datetime | None = None
    efeito_financeiro: str = "nenhum"  # nenhum | pendente_financeiro | executado
    protocolo: str | None = None
    id: str | None = None


class RepositorioContestacoesDecisao(Protocol):
    def disponivel(self) -> bool: ...

    def exclusivo(self, disputa_id: str) -> Any:
        """Uma escrita por vez nas contestações da disputa, até o fim da transação."""

    def disputa_id(self, pedido_id: str, aberta_em: datetime) -> str | None: ...

    def inserir(self, item: ContestacaoDecisao) -> tuple[ContestacaoDecisao, bool]:
        """(registro, criado). Uma por parte e por disputa: a repetida devolve a que existe."""

    def obter(self, contestacao_id: str) -> ContestacaoDecisao | None: ...

    def da_disputa(self, disputa_id: str) -> list[ContestacaoDecisao]: ...

    def listar(
        self,
        status: str | None = None,
        efeito: str | None = None,
        pedido_id: str | None = None,
        vencidas_em: datetime | None = None,
        limite: int = 50,
        deslocamento: int = 0,
    ) -> tuple[list[ContestacaoDecisao], int]: ...

    def atualizar(self, item: ContestacaoDecisao, status_esperado: str) -> bool:
        """Grava a análise só se o status ainda for o esperado."""


class ContestacoesDecisaoEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, ContestacaoDecisao] = {}
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    @contextmanager
    def exclusivo(self, disputa_id: str) -> Iterator[None]:
        with self._trava:
            yield

    def disputa_id(self, pedido_id: str, aberta_em: datetime) -> str | None:
        return str(uuid.uuid5(uuid.NAMESPACE_URL, f"{pedido_id}:{aberta_em.isoformat()}"))

    def inserir(self, item: ContestacaoDecisao) -> tuple[ContestacaoDecisao, bool]:
        with self._trava:
            for c in self._itens.values():
                if (c.disputa_id, c.contestante_id) == (item.disputa_id, item.contestante_id):
                    return c, False
            numero = len(self._itens) + 1
            novo = replace(
                item,
                id=str(uuid.uuid4()),
                protocolo=f"CDS-{item.aberta_em.year}-{numero:06d}",
            )
            self._itens[novo.id] = novo  # type: ignore[index]
            return novo, True

    def obter(self, contestacao_id: str) -> ContestacaoDecisao | None:
        return self._itens.get(contestacao_id)

    def da_disputa(self, disputa_id: str) -> list[ContestacaoDecisao]:
        itens = [c for c in self._itens.values() if c.disputa_id == disputa_id]
        return sorted(itens, key=lambda c: c.aberta_em)

    def listar(
        self,
        status: str | None = None,
        efeito: str | None = None,
        pedido_id: str | None = None,
        vencidas_em: datetime | None = None,
        limite: int = 50,
        deslocamento: int = 0,
    ) -> tuple[list[ContestacaoDecisao], int]:
        itens = [
            c
            for c in self._itens.values()
            if (status is None or c.status == status)
            and (efeito is None or c.efeito_financeiro == efeito)
            and (pedido_id is None or c.pedido_id == pedido_id)
            and (vencidas_em is None or (c.status in PENDENTES and c.responder_ate < vencidas_em))
        ]
        itens.sort(key=lambda c: (c.responder_ate, c.protocolo or ""))
        return itens[deslocamento : deslocamento + limite], len(itens)

    def atualizar(self, item: ContestacaoDecisao, status_esperado: str) -> bool:
        with self._trava:
            atual = self._itens.get(item.id or "")
            if atual is None or atual.status != status_esperado:
                return False
            self._itens[item.id] = item  # type: ignore[index]
            return True


_SELECT = (
    "select id, protocolo, disputa_id, pedido_id, contestante_id, o_que_faltou, anexos, canal, "
    "aberta_em, contestar_ate, responder_ate, status, analista_id, resposta, nova_decisao, "
    "novo_valor_reembolso_centavos, aprovada_por, decidida_em, efeito_financeiro "
    "from public.disputa_contestacoes "
)


def _texto(valor: Any) -> str | None:
    return None if valor is None else str(valor)


def _montar(r: dict[str, Any]) -> ContestacaoDecisao:
    valor = r["novo_valor_reembolso_centavos"]
    return ContestacaoDecisao(
        id=str(r["id"]),
        protocolo=r["protocolo"],
        disputa_id=str(r["disputa_id"]),
        pedido_id=str(r["pedido_id"]),
        contestante_id=str(r["contestante_id"]),
        o_que_faltou=r["o_que_faltou"],
        anexos=tuple(str(a) for a in r["anexos"]),
        canal=r["canal"],
        aberta_em=r["aberta_em"],
        contestar_ate=r["contestar_ate"],
        responder_ate=r["responder_ate"],
        status=r["status"],
        analista_id=_texto(r["analista_id"]),
        resposta=r["resposta"],
        nova_decisao=r["nova_decisao"],
        novo_valor_reembolso_centavos=None if valor is None else int(valor),
        aprovada_por=_texto(r["aprovada_por"]),
        decidida_em=r["decidida_em"],
        efeito_financeiro=r["efeito_financeiro"],
    )


class ContestacoesDecisaoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return con.execute(
                "select to_regclass('public.disputa_contestacoes') is not null as ok"
            ).fetchone()["ok"]

    @contextmanager
    def exclusivo(self, disputa_id: str) -> Iterator[None]:
        with self._banco.transacao() as con:
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                (f"disputa_contestacoes:{disputa_id}",),
            )
            yield

    def disputa_id(self, pedido_id: str, aberta_em: datetime) -> str | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            r = con.execute(
                "select id from public.disputas where pedido_id = %s and aberta_em = %s",
                (pid, aberta_em),
            ).fetchone()
        return str(r["id"]) if r else None

    def inserir(self, item: ContestacaoDecisao) -> tuple[ContestacaoDecisao, bool]:
        disputa = exigir_uuid(item.disputa_id, "disputa")
        contestante = exigir_uuid(item.contestante_id, "contestante")
        with self._banco.transacao() as con:
            criado = con.execute(
                "insert into public.disputa_contestacoes (disputa_id, pedido_id, contestante_id, "
                "o_que_faltou, anexos, canal, aberta_em, contestar_ate, responder_ate) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "on conflict (disputa_id, contestante_id) do nothing returning id",
                (
                    disputa,
                    exigir_uuid(item.pedido_id, "pedido"),
                    contestante,
                    item.o_que_faltou,
                    Jsonb(list(item.anexos)),
                    item.canal,
                    item.aberta_em,
                    item.contestar_ate,
                    item.responder_ate,
                ),
            ).fetchone()
            linha = con.execute(
                _SELECT + "where disputa_id = %s and contestante_id = %s", (disputa, contestante)
            ).fetchone()
        return _montar(linha), criado is not None

    def obter(self, contestacao_id: str) -> ContestacaoDecisao | None:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return None
        with self._banco.transacao() as con:
            r = con.execute(_SELECT + "where id = %s", (cid,)).fetchone()
        return _montar(r) if r else None

    def da_disputa(self, disputa_id: str) -> list[ContestacaoDecisao]:
        did = como_uuid(disputa_id)
        if did is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                _SELECT + "where disputa_id = %s order by aberta_em, id", (did,)
            ).fetchall()
        return [_montar(r) for r in linhas]

    def listar(
        self,
        status: str | None = None,
        efeito: str | None = None,
        pedido_id: str | None = None,
        vencidas_em: datetime | None = None,
        limite: int = 50,
        deslocamento: int = 0,
    ) -> tuple[list[ContestacaoDecisao], int]:
        filtros: list[str] = []
        valores: list[Any] = []
        if status is not None:
            filtros.append("status = %s")
            valores.append(status)
        if efeito is not None:
            filtros.append("efeito_financeiro = %s")
            valores.append(efeito)
        if pedido_id is not None:
            pid = como_uuid(pedido_id)
            if pid is None:
                return [], 0
            filtros.append("pedido_id = %s")
            valores.append(pid)
        if vencidas_em is not None:
            filtros.append("status = any(%s) and responder_ate < %s")
            valores.extend([list(PENDENTES), vencidas_em])
        onde = ("where " + " and ".join(filtros) + " ") if filtros else ""
        with self._banco.transacao() as con:
            total = con.execute(
                "select count(*) as n from public.disputa_contestacoes " + onde,  # noqa: S608
                valores,
            ).fetchone()["n"]
            linhas = con.execute(
                _SELECT + onde + "order by responder_ate, protocolo limit %s offset %s",
                (*valores, limite, deslocamento),
            ).fetchall()
        return [_montar(r) for r in linhas], int(total)

    def atualizar(self, item: ContestacaoDecisao, status_esperado: str) -> bool:
        cid = exigir_uuid(item.id or "", "contestação")
        with self._banco.transacao() as con:
            r = con.execute(
                "update public.disputa_contestacoes set status = %s, analista_id = %s, "
                "resposta = %s, nova_decisao = %s, novo_valor_reembolso_centavos = %s, "
                "aprovada_por = %s, decidida_em = %s, efeito_financeiro = %s "
                "where id = %s and status = %s returning id",
                (
                    item.status,
                    como_uuid(item.analista_id) if item.analista_id else None,
                    item.resposta,
                    item.nova_decisao,
                    item.novo_valor_reembolso_centavos,
                    como_uuid(item.aprovada_por) if item.aprovada_por else None,
                    item.decidida_em,
                    item.efeito_financeiro,
                    cid,
                    status_esperado,
                ),
            ).fetchone()
        return r is not None
