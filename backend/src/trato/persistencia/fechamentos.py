"""Fechamentos mensais no Postgres (tabela `fechamentos_mensais`, migration 20261108120000).

A tabela é imutável (gatilho): o que foi gravado não muda nem some. O mês é guardado como o
primeiro dia (date); aqui ele vira 'AAAA-MM'.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import date
from typing import Any

from psycopg.types.json import Jsonb

from trato.financeiro.fechamento import Fechamento, MesJaFechado
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import Duplicado


def _dia(mes: str) -> date:
    ano, numero = mes.split("-")
    return date(int(ano), int(numero), 1)


def _montar(linha: dict[str, Any]) -> Fechamento:
    return Fechamento(
        mes=linha["mes"].strftime("%Y-%m"),
        totais=dict(linha["totais"]),
        hash=linha["hash"],
        fechado_por=str(linha["fechado_por"]),
        fechado_em=linha["fechado_em"],
        motivo=linha["motivo"],
    )


class FechamentosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, mes: str) -> Fechamento | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "select mes, totais, hash, fechado_por, fechado_em, motivo "
                "from public.fechamentos_mensais where mes = %s",
                (_dia(mes),),
            ).fetchone()
        return _montar(linha) if linha else None

    def gravar(self, fechamento: Fechamento) -> None:
        f = fechamento
        try:
            with self._banco.transacao() as con:
                con.execute(
                    "insert into public.fechamentos_mensais "
                    "(mes, totais, hash, fechado_por, fechado_em, motivo) "
                    "values (%s, %s, %s, %s, %s, %s)",
                    (_dia(f.mes), Jsonb(f.totais), f.hash, f.fechado_por, f.fechado_em, f.motivo),
                )
        except Duplicado as erro:  # a transação traduz o UniqueViolation da chave (mes)
            raise MesJaFechado(f.mes) from erro

    def listar(self) -> Sequence[Fechamento]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select mes, totais, hash, fechado_por, fechado_em, motivo "
                "from public.fechamentos_mensais order by mes desc"
            ).fetchall()
        return tuple(_montar(l) for l in linhas)  # noqa: E741
