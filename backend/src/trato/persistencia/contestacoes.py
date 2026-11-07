# ruff: noqa: S608 - só as colunas fixas de _COLUNAS entram na f-string; valores vão por parâmetro.
"""Contestações de cartão no Postgres (tabela `contestacoes`, migration 20261108120000)."""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

_COLUNAS = (
    "provedor, provedor_contestacao_id, cobranca_id, pedido_id, valor_centavos, motivo, status, "
    "prazo_provas, aberta_em, atualizada_em, encerrada_em"
)


def _montar(linha: dict[str, Any]) -> Contestacao:
    return Contestacao(
        provedor=linha["provedor"],
        provedor_contestacao_id=linha["provedor_contestacao_id"],
        cobranca_id=linha["cobranca_id"],
        pedido_id=str(linha["pedido_id"]) if linha["pedido_id"] else None,
        valor_centavos=int(linha["valor_centavos"]),
        motivo=linha["motivo"],
        status=StatusContestacao(linha["status"]),
        prazo_provas=linha["prazo_provas"],
        aberta_em=linha["aberta_em"],
        atualizada_em=linha["atualizada_em"],
        encerrada_em=linha["encerrada_em"],
    )


class ContestacoesPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, provedor_contestacao_id: str) -> Contestacao | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS} from public.contestacoes where provedor_contestacao_id = %s",
                (provedor_contestacao_id,),
            ).fetchone()
        return _montar(linha) if linha else None

    def salvar(self, contestacao: Contestacao) -> None:
        c = contestacao
        # Pedido que não é uuid (ou não existe) fica sem vínculo: a contestação é guardada mesmo
        # assim, para o financeiro ver.
        pedido = como_uuid(c.pedido_id) if c.pedido_id else None
        with self._banco.transacao() as con:
            if pedido is not None:
                existe = con.execute(
                    "select 1 from public.pedidos where id = %s", (pedido,)
                ).fetchone()
                pedido = pedido if existe else None
            con.execute(
                f"insert into public.contestacoes ({_COLUNAS}) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "on conflict (provedor, provedor_contestacao_id) do update set "
                "cobranca_id = excluded.cobranca_id, pedido_id = excluded.pedido_id, "
                "valor_centavos = excluded.valor_centavos, motivo = excluded.motivo, "
                "status = excluded.status, prazo_provas = excluded.prazo_provas, "
                "atualizada_em = excluded.atualizada_em, encerrada_em = excluded.encerrada_em",
                (
                    c.provedor, c.provedor_contestacao_id, c.cobranca_id, pedido,
                    c.valor_centavos, c.motivo, c.status.value, c.prazo_provas, c.aberta_em,
                    c.atualizada_em, c.encerrada_em,
                ),
            )  # fmt: skip

    def listar(self) -> Sequence[Contestacao]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.contestacoes order by aberta_em desc"
            ).fetchall()
        return tuple(_montar(l) for l in linhas)  # noqa: E741

    def abertas_do_pedido(self, pedido_id: str) -> Sequence[Contestacao]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.contestacoes "
                "where pedido_id = %s and status in ('aberta', 'em_analise') "
                "order by aberta_em desc",
                (pid,),
            ).fetchall()
        return tuple(_montar(l) for l in linhas)  # noqa: E741
