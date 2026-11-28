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
    # Só nas rotas do pedido contratado: cliente com a conta bloqueada (Termos 20.6 e 20.10).
    bloqueado: bool = False


class ProvedorAuth(Protocol):
    def autenticar(self, token: str) -> Usuario | None:
        """Devolve o usuário do token, ou `None` se o token não vale."""

    def conta_bloqueada(self, token: str) -> bool:
        """O token é válido, mas a conta está bloqueada (para recusar com 403, não 401)."""


class ProvedorAuthFalso:
    """Só para teste: mapa fixo de token para usuário."""

    def __init__(self, usuarios: Mapping[str, Usuario]) -> None:
        self._usuarios = dict(usuarios)
        self.bloqueados: set[str] = set()  # tokens de contas bloqueadas
        self.inativos: set[str] = set()  # tokens de contas inativas (Termos 4.9)

    def autenticar(self, token: str) -> Usuario | None:
        if token in self.bloqueados or token in self.inativos:
            return None
        return self._usuarios.get(token)

    def autenticar_para_suporte(self, token: str) -> Usuario | None:
        return self._usuarios.get(token)

    def conta_bloqueada(self, token: str) -> bool:
        return token in self.bloqueados and token in self._usuarios

    def conta_inativa(self, token: str) -> bool:
        return token in self.inativos and token in self._usuarios

    def definir_inativo(self, usuario_id: str, inativo: bool) -> None:
        for tok, u in self._usuarios.items():
            if u.id == usuario_id:
                if inativo:
                    self.inativos.add(tok)
                else:
                    self.inativos.discard(tok)
