"""Reagendamentos no Postgres (tabela `public.reagendamentos`, migration 20261123232000).

A unicidade da proposta pendente é do índice único parcial: a segunda proposta simultânea cai em
`UniqueViolation`, que vira `PropostaPendente`. Responder é um UPDATE condicional (`status =
'pendente'`), então duas respostas ao mesmo tempo nunca valem as duas.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import psycopg.errors

from trato.api.reagendamentos import PropostaPendente, Reagendamento
from trato.persistencia.comum import como_uuid

_COLUNAS = (
    "id, pedido_id, proposto_por, nova_janela_inicio, nova_janela_fim, motivo, status, "
    "respondido_por, respondido_em, criado_em"
)


def _reagendamento(l: dict[str, Any]) -> Reagendamento:  # noqa: E741
    return Reagendamento(
        id=str(l["id"]),
        pedido_id=str(l["pedido_id"]),
        proposto_por=str(l["proposto_por"]),
        nova_janela_inicio=l["nova_janela_inicio"],
        nova_janela_fim=l["nova_janela_fim"],
        motivo=l["motivo"],
        status=l["status"],
        criado_em=l["criado_em"],
        respondido_por=str(l["respondido_por"]) if l["respondido_por"] else None,
        respondido_em=l["respondido_em"],
    )


class ReagendamentosPostgres:
    def __init__(self, banco: Any) -> None:
        self._banco = banco

    def propor(
        self,
        pedido_id: str,
        proposto_por: str,
        inicio: datetime,
        fim: datetime,
        motivo: str,
        agora: datetime,
    ) -> Reagendamento:
        try:
            with self._banco.transacao() as con:
                linha = con.execute(
                    "insert into public.reagendamentos (pedido_id, proposto_por, "  # noqa: S608
                    "nova_janela_inicio, nova_janela_fim, motivo, criado_em) "
                    f"values (%s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                    (pedido_id, proposto_por, inicio, fim, motivo, agora),
                ).fetchone()
        except psycopg.errors.UniqueViolation:
            raise PropostaPendente from None
        return _reagendamento(linha)

    def obter(self, reagendamento_id: str) -> Reagendamento | None:
        uid = como_uuid(reagendamento_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS} from public.reagendamentos where id = %s",  # noqa: S608
                (uid,),
            ).fetchone()
        return _reagendamento(linha) if linha else None

    def listar(self, pedido_id: str) -> list[Reagendamento]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.reagendamentos "  # noqa: S608
                "where pedido_id = %s order by criado_em desc, id",
                (pedido_id,),
            ).fetchall()
        return [_reagendamento(l) for l in linhas]  # noqa: E741

    def responder(
        self, reagendamento_id: str, status: str, por: str, agora: datetime
    ) -> Reagendamento | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.reagendamentos set status = %s, respondido_por = %s, "  # noqa: S608
                f"respondido_em = %s where id = %s and status = 'pendente' returning {_COLUNAS}",
                (status, por, agora, reagendamento_id),
            ).fetchone()
        return _reagendamento(linha) if linha else None
