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
    ResultadoCliente,
    ResultadoDevolucao,
    ResultadoResposta,
    ResultadoSolicitacao,
)
from trato.persistencia.comum import como_uuid, exigir_uuid

_COLUNAS = (
    "id, profissional_id, cliente_id, pedido_id, status, moedas_cobradas, chave_idempotencia, "
    "criada_em, responder_ate, respondida_em, expira_em, encerrada_em, "
    # via jsonb: funciona também antes das colunas novas existirem
    "to_jsonb(e) ->> 'pagador' as pagador, to_jsonb(e) ->> 'orcamento_id' as orcamento_id, "
    "to_jsonb(e) ->> 'motivo_encerramento' as motivo_encerramento, "
    "(to_jsonb(e) ->> 'estornada')::boolean as estornada, "
    "(to_jsonb(e) ->> 'estornada_em')::timestamptz as estornada_em"
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
        pagador=l["pagador"] or "profissional",
        orcamento_id=_hex(l["orcamento_id"]) if l["orcamento_id"] else None,
        motivo_encerramento=l["motivo_encerramento"],
        estornada=bool(l["estornada"]),
        estornada_em=l["estornada_em"],
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

    # --- paga pelo cliente (funções da migration 20261125223000) --------------------------------

    @staticmethod
    def _tem_funcoes(con: Any) -> bool:
        return con.execute(
            "select to_regprocedure('public.exclusividade_cliente_solicitar("
            "uuid,uuid,uuid,uuid,text,timestamptz,boolean)') is not null as tem"
        ).fetchone()["tem"]

    def cliente_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem_funcoes(con)

    def saldo_livre(self, cliente_id: str, agora: datetime) -> int:
        uid = como_uuid(cliente_id)
        with self._banco.transacao() as con:
            if uid is None or not self._tem_funcoes(con):
                return 0
            l = con.execute(  # noqa: E741
                "select greatest(public.moedas_saldo(%s, 'cliente', %s) - coalesce((select "
                "sum(r.moedas) from public.moedas_reservas r where r.usuario_id = %s and "
                "r.status = 'reservada'), 0), 0) as livre",
                (uid, agora, uid),
            ).fetchone()
        return int(l["livre"])

    def do_pedido_cliente(self, pedido_id: str) -> Exclusividade | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {_COLUNAS} from public.exclusividades e "  # noqa: S608
                "where pedido_id = %s and to_jsonb(e) ->> 'pagador' = 'cliente' "
                "order by criada_em desc limit 1",
                (pid,),
            ).fetchone()
        return _exclusividade(l) if l else None

    def listar_cliente(
        self,
        pedido_id: str | None = None,
        cliente_id: str | None = None,
        status: str | None = None,
        limite: int = 20,
        deslocamento: int = 0,
    ) -> tuple[list[Exclusividade], int]:
        condicoes, valores = ["to_jsonb(e) ->> 'pagador' = 'cliente'"], []
        for coluna, valor in (("pedido_id", pedido_id), ("cliente_id", cliente_id)):
            if valor is not None:
                if como_uuid(valor) is None:
                    return [], 0
                condicoes.append(f"{coluna} = %s")
                valores.append(como_uuid(valor))
        if status is not None:
            condicoes.append("status = %s")
            valores.append(status)
        onde = " and ".join(condicoes)
        with self._banco.transacao() as con:
            total = con.execute(
                f"select count(*) as n from public.exclusividades e where {onde}",  # noqa: S608
                valores,
            ).fetchone()["n"]
            linhas = con.execute(
                f"select {_COLUNAS} from public.exclusividades e where {onde} "  # noqa: S608
                "order by criada_em desc, id limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
        return [_exclusividade(x) for x in linhas], int(total)

    def solicitar_cliente(
        self,
        cliente_id: str,
        pedido_id: str,
        profissional_id: str | None,
        orcamento_id: str | None,
        chave: str,
        agora: datetime,
        exigir_mei: bool,
        apto: Any,  # a função do banco confere quem pode orçar
    ) -> ResultadoCliente:
        with self._banco.transacao() as con:
            if not self._tem_funcoes(con):
                return ResultadoCliente("indisponivel")
            dono = con.execute(
                "select to_jsonb(e) ->> 'pagador' as pagador, cliente_id, pedido_id "
                "from public.exclusividades e where chave_idempotencia = %s",
                (chave,),
            ).fetchone()
            if dono is not None and (
                dono["pagador"] != "cliente"
                or str(dono["cliente_id"]) != str(como_uuid(cliente_id))
                or str(dono["pedido_id"]) != str(como_uuid(pedido_id))
            ):
                raise ValueError("chave de idempotência já usada em outra exclusividade")
            l = con.execute(  # noqa: E741
                "select resultado, exclusividade_id, expira_em, saldo_restante "
                "from public.exclusividade_cliente_solicitar(%s, %s, %s, %s, %s, %s, %s)",
                (
                    exigir_uuid(cliente_id, "cliente"),
                    exigir_uuid(pedido_id, "pedido"),
                    como_uuid(profissional_id) if profissional_id else None,
                    como_uuid(orcamento_id) if orcamento_id else None,
                    chave,
                    agora,
                    exigir_mei,
                ),
            ).fetchone()
        return ResultadoCliente(
            str(l["resultado"]),
            _hex(l["exclusividade_id"]) if l["exclusividade_id"] else None,
            l["expira_em"],
            int(l["saldo_restante"]) if l["saldo_restante"] is not None else None,
        )

    def _devolucao(self, sql: str, args: tuple) -> ResultadoDevolucao:
        with self._banco.transacao() as con:
            if not self._tem_funcoes(con):
                return ResultadoDevolucao("indisponivel")
            l = con.execute(sql, args).fetchone()  # noqa: E741
        return ResultadoDevolucao(str(l["resultado"]), int(l["devolvido"] or 0))

    def desistir_cliente(
        self, exclusividade_id: str, profissional_id: str, agora: datetime
    ) -> ResultadoDevolucao:
        eid = como_uuid(exclusividade_id)
        if eid is None:
            return ResultadoDevolucao("nao_encontrada")
        return self._devolucao(
            "select resultado, devolvido from public.exclusividade_cliente_desistir(%s, %s, %s)",
            (eid, exigir_uuid(profissional_id, "profissional"), agora),
        )

    def falha_trato(
        self, exclusividade_id: str, analista_id: str, motivo: str, agora: datetime
    ) -> ResultadoDevolucao:
        eid, analista = como_uuid(exclusividade_id), como_uuid(analista_id)
        if eid is None:
            return ResultadoDevolucao("nao_encontrada")
        if analista is None:
            return ResultadoDevolucao("analista_invalido")
        return self._devolucao(
            "select resultado, devolvido "
            "from public.exclusividade_cliente_falha_trato(%s, %s, %s, %s)",
            (eid, analista, motivo, agora),
        )

    def contratar_cliente(
        self, pedido_id: str, profissional_id: str | None, agora: datetime
    ) -> list[Encerramento]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return []
        prof = como_uuid(profissional_id) if profissional_id else None
        with self._banco.transacao() as con:
            if not self._tem_funcoes(con):
                return []
            linhas = con.execute(
                "select exclusividade_id, resultado "
                "from public.exclusividade_cliente_contratar(%s, %s, %s)",
                (pid, prof, agora),
            ).fetchall()
        return [
            Encerramento(_hex(l["exclusividade_id"]), l["resultado"], profissional_id or "")  # noqa: E741
            for l in linhas  # noqa: E741
        ]

    def expirar_cliente(self, agora: datetime) -> list[Expirada]:
        with self._banco.transacao() as con:
            if not self._tem_funcoes(con):
                return []
            linhas = con.execute(
                "select exclusividade_id, profissional_id, cliente_id, pedido_id "
                "from public.exclusividade_cliente_expirar(%s)",
                (agora,),
            ).fetchall()
        return [
            Expirada(
                _hex(l["exclusividade_id"]),  # noqa: E741
                "sem_contratacao",
                _hex(l["profissional_id"]),
                _hex(l["cliente_id"]),
                _hex(l["pedido_id"]),
            )
            for l in linhas  # noqa: E741
        ]

    # --- leitura -------------------------------------------------------------------------------

    def obter(self, exclusividade_id: str) -> Exclusividade | None:
        eid = como_uuid(exclusividade_id)
        if eid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {_COLUNAS} from public.exclusividades e where id = %s",  # noqa: S608
                (eid,),
            ).fetchone()
        return _exclusividade(l) if l else None

    def do_profissional(self, profissional_id: str) -> list[Exclusividade]:
        pid = como_uuid(profissional_id)
        if pid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.exclusividades e "  # noqa: S608
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
                f"select {_COLUNAS} from public.exclusividades e "  # noqa: S608
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
                "select profissional_id from public.exclusividades e "
                "where pedido_id = %s and status = 'ativa'",
                (pid,),
            ).fetchone()
        return _hex(l["profissional_id"]) if l else None
