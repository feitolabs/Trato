"""Guardas de Pedido (processo ou investigação) e situação da retenção (Termos 14.8 e 16.3;
migration 20261127190500). Só abre, encerra e consulta: nada aqui apaga nem anonimiza.

As regras vivem no banco; em memória `disponivel()` é falso e as rotas respondem 503.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class GuardaPedido:
    id: str
    pedido_id: str
    tipo: str  # processo | investigacao
    motivo: str
    criada_por: str
    criada_em: datetime
    encerrada_em: datetime | None = None
    encerrada_por: str | None = None


@dataclass(frozen=True)
class SituacaoRetencao:
    pedido_id: str
    situacao: str  # sem_marco | no_prazo | bloqueado | vencido
    concluido_em: datetime | None
    prazo_anos: int
    guarda_ate: datetime | None
    bloqueios: tuple[str, ...]


class PedidoGuardasEmMemoria:
    def disponivel(self) -> bool:
        return False


class PedidoGuardasPostgres:
    _SELECT = (
        "select id, pedido_id, tipo, motivo, criada_por, criada_em, encerrada_em, "
        "encerrada_por from public.pedido_guardas "
    )

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            linha = con.execute(
                "select to_regclass('public.pedido_guardas') is not null "
                "and to_regprocedure('public.retencao_pedido_situacao(uuid,timestamptz)') "
                "is not null as tem"
            ).fetchone()
        return bool(linha["tem"])

    @staticmethod
    def _guarda(linha: dict[str, Any]) -> GuardaPedido:
        return GuardaPedido(
            str(linha["id"]),
            str(linha["pedido_id"]),
            linha["tipo"],
            linha["motivo"],
            str(linha["criada_por"]),
            linha["criada_em"],
            linha["encerrada_em"],
            str(linha["encerrada_por"]) if linha["encerrada_por"] else None,
        )

    def listar(self, pedido_id: str) -> list[GuardaPedido]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                self._SELECT + "where pedido_id = %s order by criada_em desc, id", (pid,)
            ).fetchall()
        return [self._guarda(x) for x in linhas]

    def abrir(
        self, pedido_id: str, tipo: str, motivo: str, operador_id: str
    ) -> tuple[GuardaPedido, bool]:
        """(guarda, nova). A mesma guarda ainda aberta (tipo e motivo) é devolvida."""
        pid = exigir_uuid(pedido_id, "pedido")
        operador = exigir_uuid(operador_id, "operador")
        with self._banco.transacao() as con:
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                (f"pedido-guarda:{pid}",),
            )
            existente = con.execute(
                self._SELECT + "where pedido_id = %s and tipo = %s and motivo = %s "
                "and encerrada_em is null",
                (pid, tipo, motivo),
            ).fetchone()
            if existente is not None:
                return self._guarda(existente), False
            linha = con.execute(
                "insert into public.pedido_guardas (pedido_id, tipo, motivo, criada_por) "
                "values (%s, %s, %s, %s) returning *",
                (pid, tipo, motivo, operador),
            ).fetchone()
        return self._guarda(linha), True

    def encerrar(
        self, pedido_id: str, guarda_id: str, operador_id: str
    ) -> tuple[GuardaPedido | None, bool]:
        """(guarda, encerrou agora). `None`: não existe neste pedido."""
        pid, gid = como_uuid(pedido_id), como_uuid(guarda_id)
        if pid is None or gid is None:
            return None, False
        operador = exigir_uuid(operador_id, "operador")
        with self._banco.transacao() as con:
            atual = con.execute(
                self._SELECT + "where id = %s and pedido_id = %s for update", (gid, pid)
            ).fetchone()
            if atual is None:
                return None, False
            if atual["encerrada_em"] is not None:
                return self._guarda(atual), False
            linha = con.execute(
                "update public.pedido_guardas set encerrada_em = now(), encerrada_por = %s "
                "where id = %s returning *",
                (operador, gid),
            ).fetchone()
        return self._guarda(linha), True

    def situacao(self, pedido_id: str) -> SituacaoRetencao | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select * from public.retencao_pedido_situacao(%s)", (pid,)
            ).fetchone()
        if linha is None:
            return None
        return SituacaoRetencao(
            str(linha["pedido_id"]),
            linha["situacao"],
            linha["concluido_em"],
            int(linha["prazo_anos"]),
            linha["guarda_ate"],
            tuple(linha["bloqueios"] or ()),
        )
