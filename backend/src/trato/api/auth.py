"""Autenticação como dependência injetável.

O usuário e o papel vêm de um `ProvedorAuth` abstrato. A ligação ao Supabase Auth (validar o
JWT e ler o papel em `perfis_profissional` e `equipe`) virá depois; os testes usam
`ProvedorAuthFalso`.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol


class PapelUsuario(StrEnum):
    CLIENTE = "cliente"
    PROFISSIONAL = "profissional"
    EQUIPE = "equipe"


@dataclass(frozen=True)
class Usuario:
    id: str
    papel: PapelUsuario


class ProvedorAuth(Protocol):
    def autenticar(self, token: str) -> Usuario | None:
        """Devolve o usuário do token, ou `None` se o token não vale."""


class ProvedorAuthFalso:
    """Só para teste: mapa fixo de token para usuário."""

    def __init__(self, usuarios: Mapping[str, Usuario]) -> None:
        self._usuarios = dict(usuarios)

    def autenticar(self, token: str) -> Usuario | None:
        return self._usuarios.get(token)
