"""Autenticação com o JWT do Supabase Auth.

O token é validado (assinatura, expiração, audiência) com o segredo HS256 OU as chaves públicas
(JWKS) do projeto, ambos lidos do .env. O `sub` do token é o `usuarios.id`; o papel
(cliente, profissional, equipe) vem do BANCO, nunca de uma afirmação do token.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

import jwt
from jwt import PyJWKClient

from trato.api.auth import Usuario
from trato.persistencia.usuarios import STATUS_QUE_ENTRAM, UsuariosPostgres

_ASSIMETRICOS = ("RS256", "ES256")


class ProvedorAuthSupabase:
    def __init__(
        self,
        usuarios: UsuariosPostgres,
        *,
        segredo_hs256: Callable[[], str] | None = None,
        jwks_url: str = "",
        audiencia: str = "authenticated",
    ) -> None:
        self._usuarios = usuarios
        self._segredo = segredo_hs256
        self._jwks = PyJWKClient(jwks_url, cache_keys=True) if jwks_url else None
        self._audiencia = audiencia

    def _decodificar(self, token: str) -> dict[str, Any]:
        algoritmo = jwt.get_unverified_header(token).get("alg")
        if algoritmo == "HS256" and self._segredo is not None:
            segredo = self._segredo()
            if not segredo:
                raise jwt.InvalidTokenError("segredo HS256 não configurado")
            chave: Any = segredo
        elif algoritmo in _ASSIMETRICOS and self._jwks is not None:
            chave = self._jwks.get_signing_key_from_jwt(token).key
        else:
            raise jwt.InvalidAlgorithmError("algoritmo não aceito")
        return jwt.decode(
            token,
            chave,
            algorithms=[algoritmo],
            audience=self._audiencia,
            options={"require": ["exp", "sub"]},
        )

    def autenticar(self, token: str) -> Usuario | None:
        try:
            claims = self._decodificar(token)
        except jwt.PyJWTError:
            return None
        perfil = self._usuarios.perfil(str(claims["sub"]))
        if perfil is None or perfil.status not in STATUS_QUE_ENTRAM:
            return None
        return Usuario(perfil.id, perfil.papel)
