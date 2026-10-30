"""Auditoria imutável com cadeia de hash. A gravação passa só por `registrar_auditoria()`."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, para_json
from trato.persistencia.conexao import Banco

TIPOS_ATOR = ("cliente", "profissional", "equipe", "sistema")


@dataclass(frozen=True)
class RegistroAuditoria:
    id: int
    ocorrida_em: datetime
    ator_id: str | None
    ator_tipo: str
    acao: str
    entidade: str | None
    entidade_id: str | None
    antes: Any
    depois: Any
    motivo: str | None


def registrar_na_transacao(
    con: psycopg.Connection[Any],
    *,
    ator_id: str | None,
    ator_tipo: str,
    acao: str,
    entidade: str | None = None,
    entidade_id: str | None = None,
    antes: Any = None,
    depois: Any = None,
    motivo: str | None = None,
    ip: str | None = None,
    dispositivo: str | None = None,
    request_id: str | None = None,
) -> int:
    """Grava na MESMA transação de quem chama: ou a mudança e a trilha entram, ou nenhuma."""
    linha = con.execute(
        "select public.registrar_auditoria("
        "%s::uuid, %s, %s, %s, %s::uuid, %s, %s, %s, %s, %s, %s) as id",
        (
            como_uuid(ator_id) if ator_id else None,
            ator_tipo,
            acao,
            entidade,
            como_uuid(entidade_id) if entidade_id else None,
            Jsonb(para_json(antes)) if antes is not None else None,
            Jsonb(para_json(depois)) if depois is not None else None,
            motivo,
            ip,
            dispositivo,
            request_id,
        ),
    ).fetchone()
    return int(linha["id"])


class AuditoriaPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def registrar(self, **campos: Any) -> int:
        with self._banco.transacao() as con:
            return registrar_na_transacao(con, **campos)

    def da_entidade(self, entidade: str, entidade_id: str) -> Sequence[RegistroAuditoria]:
        achado = como_uuid(entidade_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, ocorrida_em, ator_id, ator_tipo, acao, entidade, entidade_id, "
                "antes, depois, motivo from public.auditoria "
                "where entidade = %s and entidade_id = %s::uuid order by id",
                (entidade, achado),
            ).fetchall()
        return tuple(
            RegistroAuditoria(
                l["id"],
                l["ocorrida_em"],
                _txt(l["ator_id"]),
                l["ator_tipo"],
                l["acao"],
                l["entidade"],
                _txt(l["entidade_id"]),
                l["antes"],
                l["depois"],
                l["motivo"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def verificar_cadeia(self) -> int | None:
        """None = cadeia íntegra; senão, o id da primeira linha adulterada ou removida."""
        with self._banco.transacao() as con:
            return con.execute(
                "select public.verificar_cadeia_auditoria() as primeira_falha"
            ).fetchone()["primeira_falha"]


def _txt(valor: object) -> str | None:
    return None if valor is None else str(valor)
