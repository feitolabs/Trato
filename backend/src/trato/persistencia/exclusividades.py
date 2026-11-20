"""Exclusividades no Postgres: chama as 4 funções SQL atômicas (migration 20261121200000).

O dinheiro (débito e estorno no livro `moedas_lancamentos`, carteira 'profissional') e a corrida
(travas, limite, saldo) ficam DENTRO das funções, como na reserva de desconto. Este módulo só
traduz parâmetros e linhas. As funções de aceite e de expiração já gravam o histórico do pedido
e a mudança `aberto <-> reservado`; `encerrar_por_pedido` não muda o estado do pedido (o backend
muda).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from trato.api.exclusividades import (
    Encerramento,
    Exclusividade,
    Expirada,
    ResultadoResposta,
    ResultadoSolicitacao,
)
from trato.persistencia.comum import como_uuid, exigir_uuid

_COLUNAS = (
    "id, profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia, "
    "criada_em, responder_ate, respondida_em, expira_em, encerrada_em"
)


def _hex(valor: Any) -> str:
    return uuid.UUID(str(valor)).hex


def _exclusividade(l: dict[str, Any]) -> Exclusividade:  # noqa: E741
    return Exclusividade(
        id=_hex(l["id"]),
        profissional_id=_hex(l["profissional_id"]),
        cliente_id=_hex(l["cliente_id"]),
        pedido_id=_hex(l["pedido_id"]),
        status=l["status"],
        moedas_cobradas=int(l["moedas_cobradas"]),
        chave_idempotencia=l["chave_idempotencia"],
        criada_em=l["criada_em"],
        responder_ate=l["responder_ate"],
        respondida_em=l["respondida_em"],
        expira_em=l["expira_em"],
        encerrada_em=l["encerrada_em"],
    )


class ExclusividadesPostgres:
    def __init__(self, banco: Any) -> None:
        self._banco = banco

    def solicitar(
        self,
        profissional_id: str,
        pedido_id: str,
        chave: str,
        agora: datetime,
        custo: int,
        max_simultaneas: int,
        prazo_resposta_horas: int,
        bloqueio_recusa_dias: int,
    ) -> ResultadoSolicitacao:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select resultado, exclusividade_id, responder_ate, saldo_restante "
                "from public.exclusividade_solicitar(%s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    exigir_uuid(profissional_id, "profissional"),
                    exigir_uuid(pedido_id, "pedido"),
                    chave,
                    agora,
                    custo,
                    max_simultaneas,
                    prazo_resposta_horas,
                    bloqueio_recusa_dias,
                ),
            ).fetchone()
        return ResultadoSolicitacao(
            resultado=str(l["resultado"]),
            exclusividade_id=_hex(l["exclusividade_id"]) if l["exclusividade_id"] else None,
            responder_ate=l["responder_ate"],
            saldo_restante=int(l["saldo_restante"]) if l["saldo_restante"] is not None else None,
        )

    def responder(
        self,
        exclusividade_id: str,
        cliente_id: str,
        decisao: str,
        agora: datetime,
        duracao_horas: int,
    ) -> ResultadoResposta:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select resultado, expira_em "
                "from public.exclusividade_responder(%s, %s, %s, %s, %s)",
                (
                    exigir_uuid(exclusividade_id, "exclusividade"),
                    exigir_uuid(cliente_id, "cliente"),
                    decisao,
                    agora,
                    duracao_horas,
                ),
            ).fetchone()
        return ResultadoResposta(str(l["resultado"]), l["expira_em"])

    def expirar(self, agora: datetime) -> list[Expirada]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select exclusividade_id, motivo, profissional_id, cliente_id, pedido_id "
                "from public.exclusividade_expirar(%s)",
                (agora,),
            ).fetchall()
        return [
            Expirada(
                _hex(l["exclusividade_id"]),  # noqa: E741
                l["motivo"],
                _hex(l["profissional_id"]),
                _hex(l["cliente_id"]),
                _hex(l["pedido_id"]),
            )
            for l in linhas  # noqa: E741
        ]

    def encerrar_por_pedido(
        self, pedido_id: str, profissional_aceito: str | None, agora: datetime
    ) -> list[Encerramento]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select exclusividade_id, resultado, profissional_id "
                "from public.exclusividade_encerrar_por_pedido(%s, %s, %s)",
                (exigir_uuid(pedido_id, "pedido"), como_uuid(profissional_aceito), agora),
            ).fetchall()
        return [
            Encerramento(_hex(l["exclusividade_id"]), l["resultado"], _hex(l["profissional_id"]))  # noqa: E741
            for l in linhas  # noqa: E741
        ]

    # --- leitura -------------------------------------------------------------------------------

    def obter(self, exclusividade_id: str) -> Exclusividade | None:
        eid = como_uuid(exclusividade_id)
        if eid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {_COLUNAS} from public.exclusividades where id = %s",  # noqa: S608
                (eid,),
            ).fetchone()
        return _exclusividade(l) if l else None

    def do_profissional(self, profissional_id: str) -> list[Exclusividade]:
        pid = como_uuid(profissional_id)
        if pid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.exclusividades "  # noqa: S608
                "where profissional_id = %s order by criada_em desc limit 100",
                (pid,),
            ).fetchall()
        return [_exclusividade(l) for l in linhas]  # noqa: E741

    def em_andamento_do_pedido(self, pedido_id: str) -> Exclusividade | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {_COLUNAS} from public.exclusividades "  # noqa: S608
                "where pedido_id = %s and status in ('aguardando_cliente', 'ativa')",
                (pid,),
            ).fetchone()
        return _exclusividade(l) if l else None

    def profissional_ativo_do_pedido(self, pedido_id: str) -> str | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select profissional_id from public.exclusividades "
                "where pedido_id = %s and status = 'ativa'",
                (pid,),
            ).fetchone()
        return _hex(l["profissional_id"]) if l else None
