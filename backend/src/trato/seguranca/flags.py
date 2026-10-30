"""Sinais (flags) para revisão humana. A decisão automática NUNCA suspende, bloqueia ou pune uma
conta (V2): só abre uma flag que a equipe confirma ou descarta. Bloqueios temporários de envio
de SMS e de taxa são limitação de uso, não punição, e expiram sozinhos.
"""

from __future__ import annotations

import itertools
import threading
from collections.abc import Sequence
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from typing import Any, Protocol

TIPOS_FLAG = (
    "conta_duplicada",
    "contorno_plataforma",
    "sms_pumping",
    "abuso_limite_taxa",
)
STATUS_FLAG = ("aberta", "confirmada", "descartada")


@dataclass(frozen=True)
class Flag:
    id: str
    tipo: str
    severidade: str  # baixa | media | alta
    usuario_id: str | None
    motivos: tuple[str, ...]
    detalhes: dict[str, Any] = field(default_factory=dict)  # só dado opaco, sem dado pessoal
    status: str = "aberta"
    criada_em: datetime = field(default_factory=lambda: datetime.now(UTC))
    revisada_por: str | None = None
    revisada_em: datetime | None = None
    nota_revisao: str | None = None


class RepositorioFlags(Protocol):
    def criar(self, flag: Flag) -> Flag: ...
    def obter(self, flag_id: str) -> Flag | None: ...
    def listar(self, status: str | None = None) -> Sequence[Flag]: ...
    def atualizar(self, flag: Flag) -> None: ...
    def novo_id(self) -> str: ...


class FlagsEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Flag] = {}
        self._ids = itertools.count(1)
        self._trava = threading.Lock()

    def novo_id(self) -> str:
        return f"flag-{next(self._ids)}"

    def criar(self, flag: Flag) -> Flag:
        with self._trava:
            self._itens[flag.id] = flag
        return flag

    def obter(self, flag_id: str) -> Flag | None:
        return self._itens.get(flag_id)

    def listar(self, status: str | None = None) -> Sequence[Flag]:
        return tuple(f for f in self._itens.values() if status is None or f.status == status)

    def atualizar(self, flag: Flag) -> None:
        with self._trava:
            self._itens[flag.id] = flag


def revisar(
    repo: RepositorioFlags,
    flag_id: str,
    decisao: str,
    revisor_id: str,
    nota: str | None,
    agora: datetime,
) -> Flag | None:
    flag = repo.obter(flag_id)
    if flag is None:
        return None
    novo = replace(
        flag,
        status="confirmada" if decisao == "confirmar" else "descartada",
        revisada_por=revisor_id,
        revisada_em=agora,
        nota_revisao=nota,
    )
    repo.atualizar(novo)
    return novo
