"""Recorrências no Postgres (migration 20261124002000: `recorrencias` e `recorrencia_visitas`).

Toda mudança de status é UPDATE condicional (`where status in (...)`); a visita é única por
série e data (índice `ux_recorrencia_visitas_recorrencia_data`), então gerar duas vezes é inócuo.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from trato.api.recorrencias import (
    ST_ATIVA,
    ST_CANCELADA,
    V_AGENDADA,
    ConfigRecorrencia,
    JaExisteRecorrencia,
    Recorrencia,
    Visita,
)
from trato.persistencia.comum import como_uuid

_COLS = (
    "id, cliente_id, profissional_id, pedido_origem_id, categoria_id, frequencia, valor_centavos, "
    "valor_proposto_centavos, proxima_visita_em, status, proposto_por, cancelado_por, "
    "cancelado_em, criado_em"
)
_COLS_VISITA = "id, recorrencia_id, data_prevista_em, status, pedido_id, pulada_por, criado_em"


def _t(valor: Any) -> str | None:
    return str(valor) if valor is not None else None


def _rec(l: dict[str, Any]) -> Recorrencia:  # noqa: E741
    return Recorrencia(
        id=str(l["id"]),
        cliente_id=str(l["cliente_id"]),
        profissional_id=str(l["profissional_id"]),
        pedido_origem_id=str(l["pedido_origem_id"]),
        categoria_id=_t(l["categoria_id"]),
        frequencia=l["frequencia"],
        valor_centavos=int(l["valor_centavos"]),
        valor_proposto_centavos=l["valor_proposto_centavos"],
        proxima_visita_em=l["proxima_visita_em"],
        status=l["status"],
        proposto_por=str(l["proposto_por"]),
        cancelado_por=_t(l["cancelado_por"]),
        cancelado_em=l["cancelado_em"],
        criado_em=l["criado_em"],
    )


def _visita(l: dict[str, Any]) -> Visita:  # noqa: E741
    return Visita(
        id=str(l["id"]),
        recorrencia_id=str(l["recorrencia_id"]),
        data_prevista_em=l["data_prevista_em"],
        status=l["status"],
        criado_em=l["criado_em"],
        pedido_id=_t(l["pedido_id"]),
        pulada_por=_t(l["pulada_por"]),
    )


class RecorrenciasPostgres:
    def __init__(self, banco: Any, config: ConfigRecorrencia | None = None) -> None:
        self._banco = banco
        self._config = config or ConfigRecorrencia()

    def config(self) -> ConfigRecorrencia:
        return self._config

    def criar(self, rec: Recorrencia) -> Recorrencia:
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.recorrencias (id, cliente_id, profissional_id, "  # noqa: S608
                "pedido_origem_id, categoria_id, frequencia, valor_centavos, proxima_visita_em, "
                "status, proposto_por, criado_em) "
                "select %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s "
                "where not exists (select 1 from public.recorrencias "
                "where pedido_origem_id = %s and status <> 'cancelada') "
                f"returning {_COLS}",
                (
                    rec.id,
                    rec.cliente_id,
                    rec.profissional_id,
                    rec.pedido_origem_id,
                    rec.categoria_id,
                    rec.frequencia,
                    rec.valor_centavos,
                    rec.proxima_visita_em,
                    rec.status,
                    rec.proposto_por,
                    rec.criado_em,
                    rec.pedido_origem_id,
                ),
            ).fetchone()
        if linha is None:
            raise JaExisteRecorrencia
        return _rec(linha)

    def obter(self, recorrencia_id: str) -> Recorrencia | None:
        uid = como_uuid(recorrencia_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLS} from public.recorrencias where id = %s",  # noqa: S608
                (uid,),
            ).fetchone()
        return _rec(linha) if linha else None

    def do_usuario(self, usuario_id: str) -> list[Recorrencia]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLS} from public.recorrencias "  # noqa: S608
                "where cliente_id = %s or profissional_id = %s order by criado_em desc, id",
                (uid, uid),
            ).fetchall()
        return [_rec(l) for l in linhas]  # noqa: E741

    def mudar_status(
        self,
        recorrencia_id: str,
        de: tuple[str, ...],
        para: str,
        agora: datetime,
        por: str | None = None,
        proxima_visita_em: datetime | None = None,
    ) -> bool:
        cancelando = para == ST_CANCELADA
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.recorrencias set status = %s, atualizado_em = %s, "
                "cancelado_por = case when %s then %s else cancelado_por end, "
                "cancelado_em = case when %s then %s else cancelado_em end, "
                "proxima_visita_em = coalesce(%s, proxima_visita_em) "
                "where id = %s and status = any(%s) returning id",
                (
                    para,
                    agora,
                    cancelando,
                    por,
                    cancelando,
                    agora,
                    proxima_visita_em,
                    recorrencia_id,
                    list(de),
                ),
            ).fetchone()
        return linha is not None

    def _atualizar(self, sql: str, parametros: tuple[Any, ...]) -> bool:
        with self._banco.transacao() as con:
            return con.execute(sql, parametros).fetchone() is not None

    def propor_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        return self._atualizar(
            "update public.recorrencias set valor_proposto_centavos = %s, atualizado_em = now() "
            "where id = %s and status in ('ativa', 'pausada') "
            "and valor_proposto_centavos is null returning id",
            (valor_centavos, recorrencia_id),
        )

    def aceitar_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        return self._atualizar(
            "update public.recorrencias set valor_centavos = valor_proposto_centavos, "
            "valor_proposto_centavos = null, atualizado_em = now() "
            "where id = %s and valor_proposto_centavos = %s "
            "and status in ('ativa', 'pausada') returning id",
            (recorrencia_id, valor_centavos),
        )

    def recusar_reajuste(self, recorrencia_id: str) -> bool:
        return self._atualizar(
            "update public.recorrencias set valor_proposto_centavos = null, "
            "atualizado_em = now() where id = %s and valor_proposto_centavos is not null "
            "returning id",
            (recorrencia_id,),
        )

    def avancar(self, recorrencia_id: str, de_data: datetime, para_data: datetime) -> bool:
        return self._atualizar(
            "update public.recorrencias set proxima_visita_em = %s, atualizado_em = now() "
            "where id = %s and proxima_visita_em = %s and status = 'ativa' returning id",
            (para_data, recorrencia_id, de_data),
        )

    def visitas(self, recorrencia_id: str) -> list[Visita]:
        uid = como_uuid(recorrencia_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLS_VISITA} from public.recorrencia_visitas "  # noqa: S608
                "where recorrencia_id = %s order by data_prevista_em desc, id",
                (uid,),
            ).fetchall()
        return [_visita(l) for l in linhas]  # noqa: E741

    def obter_visita(self, visita_id: str) -> Visita | None:
        uid = como_uuid(visita_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLS_VISITA} from public.recorrencia_visitas where id = %s",  # noqa: S608
                (uid,),
            ).fetchone()
        return _visita(linha) if linha else None

    def reservar_visita(
        self, recorrencia_id: str, data: datetime, agora: datetime, status: str = V_AGENDADA
    ) -> Visita | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.recorrencia_visitas (recorrencia_id, data_prevista_em, "  # noqa: S608
                "status, criado_em) values (%s, %s, %s, %s) "
                "on conflict (recorrencia_id, data_prevista_em) do nothing "
                f"returning {_COLS_VISITA}",
                (recorrencia_id, data, status, agora),
            ).fetchone()
        return _visita(linha) if linha else None

    def vincular_pedido(self, visita_id: str, pedido_id: str) -> bool:
        return self._atualizar(
            "update public.recorrencia_visitas set pedido_id = %s where id = %s returning id",
            (pedido_id, visita_id),
        )

    def mudar_visita(
        self, visita_id: str, de: tuple[str, ...], para: str, por: str | None = None
    ) -> bool:
        return self._atualizar(
            "update public.recorrencia_visitas set status = %s, "
            "pulada_por = case when %s = 'pulada' then %s else pulada_por end "
            "where id = %s and status = any(%s) returning id",
            (para, para, por, visita_id, list(de)),
        )

    def prontas_para_gerar(self, agora: datetime) -> list[Recorrencia]:
        limite = agora + timedelta(hours=self._config.antecedencia_geracao_horas)
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLS} from public.recorrencias "  # noqa: S608
                "where status = %s and proxima_visita_em <= %s order by proxima_visita_em, id",
                (ST_ATIVA, limite),
            ).fetchall()
        return [_rec(l) for l in linhas]  # noqa: E741

    def profissional_do_pedido_de_visita(self, pedido_id: str) -> str | None:
        uid = como_uuid(pedido_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select r.profissional_id from public.recorrencia_visitas v "
                "join public.recorrencias r on r.id = v.recorrencia_id "
                "where v.pedido_id = %s limit 1",
                (uid,),
            ).fetchone()
        return str(linha["profissional_id"]) if linha else None

    def visitas_abertas(self) -> list[Visita]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLS_VISITA} from public.recorrencia_visitas "  # noqa: S608
                "where status = %s order by data_prevista_em, id",
                (V_AGENDADA,),
            ).fetchall()
        return [_visita(l) for l in linhas]  # noqa: E741
