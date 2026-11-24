"""Indique e Ganhe no Postgres (migration 20261124001000: `codigos_indicacao` e `indicacoes`).

A unicidade (um código por usuário, um vínculo por indicado) é das constraints; as mudanças de
status são UPDATEs condicionais, então duas rotinas ao mesmo tempo nunca liberam duas vezes.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from contextlib import contextmanager
from datetime import datetime
from typing import Any

import psycopg.errors

from trato.api.indicacoes import (
    STATUS_AGUARDANDO,
    STATUS_BLOQUEADO_FRAUDE,
    STATUS_CADASTRADO,
    STATUS_LIBERADO,
    ConfigIndicacao,
    Indicacao,
    JaIndicado,
)
from trato.persistencia.comum import como_uuid

_COLUNAS = (
    "id, indicador_id, indicado_id, codigo_usado, tipo, status, pedido_gatilho_id, "
    "bonus_indicador_tratinhos, bonus_indicado_tratinhos, liberacao_prevista_em, liberado_em, "
    "motivo_bloqueio, criado_em"
)


def _texto(valor: Any) -> str | None:
    return str(valor) if valor is not None else None


def _indicacao(l: dict[str, Any]) -> Indicacao:  # noqa: E741
    return Indicacao(
        id=str(l["id"]),
        indicador_id=str(l["indicador_id"]),
        indicado_id=str(l["indicado_id"]),
        codigo_usado=l["codigo_usado"],
        tipo=l["tipo"],
        status=l["status"],
        criado_em=l["criado_em"],
        bonus_indicador_tratinhos=int(l["bonus_indicador_tratinhos"]),
        bonus_indicado_tratinhos=int(l["bonus_indicado_tratinhos"]),
        pedido_gatilho_id=_texto(l["pedido_gatilho_id"]),
        liberacao_prevista_em=l["liberacao_prevista_em"],
        liberado_em=l["liberado_em"],
        motivo_bloqueio=l["motivo_bloqueio"],
    )


class IndicacoesPostgres:
    def __init__(self, banco: Any, config: ConfigIndicacao | None = None) -> None:
        self._banco = banco
        self._config = config or ConfigIndicacao()

    def config(self) -> ConfigIndicacao:
        return self._config

    def garantir_codigo(self, usuario_id: str, candidatos: Iterable[str]) -> str:
        uid = como_uuid(usuario_id)
        if uid is None:
            raise ValueError("usuário inválido")
        with self._banco.transacao() as con:
            for candidato in candidatos:
                linha = con.execute(
                    "select codigo from public.codigos_indicacao where usuario_id = %s", (uid,)
                ).fetchone()
                if linha is not None:
                    return str(linha["codigo"])
                with con.transaction():  # savepoint: colisão de código não derruba a transação
                    criado = con.execute(
                        "insert into public.codigos_indicacao (usuario_id, codigo) "
                        "values (%s, %s) on conflict do nothing returning codigo",
                        (uid, candidato),
                    ).fetchone()
                if criado is not None:
                    return str(criado["codigo"])
            linha = con.execute(
                "select codigo from public.codigos_indicacao where usuario_id = %s", (uid,)
            ).fetchone()
        if linha is None:
            raise RuntimeError("Sem código de indicação livre.")
        return str(linha["codigo"])

    def usuario_do_codigo(self, codigo: str) -> str | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "select usuario_id from public.codigos_indicacao where codigo = %s", (codigo,)
            ).fetchone()
        return str(linha["usuario_id"]) if linha else None

    def do_indicado(self, indicado_id: str) -> Indicacao | None:
        uid = como_uuid(indicado_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS} from public.indicacoes where indicado_id = %s",  # noqa: S608
                (uid,),
            ).fetchone()
        return _indicacao(linha) if linha else None

    def criar(
        self,
        indicador_id: str,
        indicado_id: str,
        codigo: str,
        tipo: str,
        bonus_indicador: int,
        bonus_indicado: int,
        agora: datetime,
        status: str = STATUS_CADASTRADO,
        motivo_bloqueio: str = "",
    ) -> Indicacao:
        try:
            with self._banco.transacao() as con:
                linha = con.execute(
                    "insert into public.indicacoes (indicador_id, indicado_id, codigo_usado, "  # noqa: S608
                    "tipo, bonus_indicador_tratinhos, bonus_indicado_tratinhos, criado_em, "
                    "status, motivo_bloqueio) "
                    f"values (%s, %s, %s, %s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                    (
                        indicador_id,
                        indicado_id,
                        codigo,
                        tipo,
                        bonus_indicador,
                        bonus_indicado,
                        agora,
                        status,
                        motivo_bloqueio,
                    ),
                ).fetchone()
        except psycopg.errors.UniqueViolation:
            raise JaIndicado from None
        return _indicacao(linha)

    def do_indicador(self, indicador_id: str) -> list[Indicacao]:
        uid = como_uuid(indicador_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.indicacoes "  # noqa: S608
                "where indicador_id = %s order by criado_em desc, id",
                (uid,),
            ).fetchall()
        return [_indicacao(l) for l in linhas]  # noqa: E741

    def recompensadas_no_mes(
        self, indicador_id: str, inicio: datetime, fim: datetime, dias_liberacao: int
    ) -> int:
        uid = como_uuid(indicador_id)
        if uid is None:
            return 0
        with self._banco.transacao() as con:
            linha = con.execute(
                "select count(*) as n from public.indicacoes "
                "where indicador_id = %s and status in ('aguardando_liberacao', 'liberado') "
                "and liberacao_prevista_em - make_interval(days => %s) >= %s "
                "and liberacao_prevista_em - make_interval(days => %s) < %s",
                (uid, dias_liberacao, inicio, dias_liberacao, fim),
            ).fetchone()
        return int(linha["n"])

    def armar(
        self,
        indicacao_id: str,
        pedido_id: str,
        bonus_indicador: int,
        liberacao_prevista_em: datetime,
    ) -> bool:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.indicacoes set status = %s, pedido_gatilho_id = %s, "
                "bonus_indicador_tratinhos = %s, liberacao_prevista_em = %s "
                "where id = %s and status = %s returning id",
                (
                    STATUS_AGUARDANDO,
                    pedido_id,
                    bonus_indicador,
                    liberacao_prevista_em,
                    indicacao_id,
                    STATUS_CADASTRADO,
                ),
            ).fetchone()
        return linha is not None

    def bloquear(self, indicacao_id: str, motivo: str, agora: datetime) -> bool:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.indicacoes set status = %s, motivo_bloqueio = %s, "
                "bonus_indicador_tratinhos = 0, bonus_indicado_tratinhos = 0 "
                "where id = %s and status = %s returning id",
                (STATUS_BLOQUEADO_FRAUDE, motivo, indicacao_id, STATUS_CADASTRADO),
            ).fetchone()
        return linha is not None

    @contextmanager
    def trava_do_indicador(self, indicador_id: str) -> Iterator[None]:
        """Advisory lock da transação por indicador: dois gatilhos do mesmo indicador se
        enfileiram (o 2º só conta o limite depois do 1º confirmar)."""
        with self._banco.transacao() as con:
            con.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", (indicador_id,))
            yield

    def vencidas(self, agora: datetime) -> list[Indicacao]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.indicacoes "  # noqa: S608
                "where status = %s and liberacao_prevista_em <= %s "
                "order by liberacao_prevista_em, id",
                (STATUS_AGUARDANDO, agora),
            ).fetchall()
        return [_indicacao(l) for l in linhas]  # noqa: E741

    def encerrar(self, indicacao_id: str, status: str, agora: datetime, motivo: str = "") -> bool:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.indicacoes set status = %s, liberado_em = %s, motivo_bloqueio = %s "
                "where id = %s and status = %s returning id",
                (
                    status,
                    agora if status == STATUS_LIBERADO else None,
                    motivo,
                    indicacao_id,
                    STATUS_AGUARDANDO,
                ),
            ).fetchone()
        return linha is not None
