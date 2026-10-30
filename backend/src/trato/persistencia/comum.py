"""Apoio dos repositórios Postgres: ids, JSON e fuso."""

from __future__ import annotations

import dataclasses
from collections.abc import Mapping
from datetime import date, datetime
from enum import Enum
from typing import Any
from uuid import UUID

from trato.persistencia.erros import DadosInvalidos


def como_uuid(valor: object) -> str | None:
    """O id como uuid canônico, ou None se não for um uuid (ex.: caminho da URL com lixo)."""
    try:
        return str(UUID(str(valor)))
    except ValueError:
        return None


def exigir_uuid(valor: object, nome: str = "id") -> str:
    achado = como_uuid(valor)
    if achado is None:
        raise DadosInvalidos(f"O {nome} informado não é válido.")
    return achado


def para_json(objeto: Any) -> Any:
    """Converte dataclasses, enums e datas em JSON puro (para as colunas jsonb)."""
    if dataclasses.is_dataclass(objeto) and not isinstance(objeto, type):
        return {c.name: para_json(getattr(objeto, c.name)) for c in dataclasses.fields(objeto)}
    if isinstance(objeto, Enum):
        return objeto.value
    if isinstance(objeto, datetime | date):
        return objeto.isoformat()
    if isinstance(objeto, Mapping):
        return {str(k): para_json(v) for k, v in objeto.items()}
    if isinstance(objeto, list | tuple | set | frozenset):
        return [para_json(v) for v in objeto]
    return objeto
