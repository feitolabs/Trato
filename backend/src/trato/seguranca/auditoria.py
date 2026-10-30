"""Eventos de segurança na auditoria. Em modo Postgres o destino é `registrar_auditoria`
(`AuditoriaPostgres`, em `contexto.extras["auditoria"]`); em memória, uma lista para os testes.

Nunca vai dado pessoal em claro no evento: só identificadores opacos (hash) e categorias.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Protocol

TIPOS_ATOR = ("cliente", "profissional", "equipe", "sistema")


class DestinoAuditoria(Protocol):
    def registrar(self, **campos: Any) -> int: ...


class AuditoriaEmMemoria:
    def __init__(self) -> None:
        self.eventos: list[dict[str, Any]] = []

    def registrar(self, **campos: Any) -> int:
        self.eventos.append({"ocorrida_em": datetime.now(UTC), **campos})
        return len(self.eventos)

    def acoes(self) -> list[str]:
        return [e["acao"] for e in self.eventos]


def emitir(
    destino: DestinoAuditoria,
    acao: str,
    *,
    ator_id: str | None = None,
    ator_tipo: str = "sistema",
    entidade: str | None = None,
    entidade_id: str | None = None,
    depois: Any = None,
    motivo: str | None = None,
    ip: str | None = None,
    dispositivo: str | None = None,
) -> None:
    """Grava o evento sem nunca derrubar a requisição: falha de auditoria vira log (sem dado
    pessoal) e a decisão de segurança já tomada continua valendo."""
    import logging

    try:
        destino.registrar(
            ator_id=ator_id if ator_tipo != "sistema" or ator_id else None,
            ator_tipo=ator_tipo if ator_tipo in TIPOS_ATOR else "sistema",
            acao=acao,
            entidade=entidade,
            entidade_id=entidade_id,
            depois=depois,
            motivo=motivo,
            ip=ip,
            dispositivo=dispositivo,
        )
    except Exception:  # noqa: BLE001 - auditoria não pode derrubar a rota
        logging.getLogger("trato.seguranca").exception("falha ao gravar auditoria: %s", acao)
