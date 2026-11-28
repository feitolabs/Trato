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
        criar_no_primeiro_login: bool = True,
        emissor: str = "",
    ) -> None:
        # B1: com o emissor configurado (`<SUPABASE_URL>/auth/v1`), token de outro projeto cai.
        self._emissor = emissor
        self._usuarios = usuarios
        self._criar_no_primeiro_login = criar_no_primeiro_login
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
            issuer=self._emissor or None,
            leeway=60,
            options={"require": ["exp", "sub", *(["iss"] if self._emissor else [])]},
        )

    def conta_bloqueada(self, token: str) -> bool:
        """Só com token válido (assinatura, prazo, audiência) de conta com status `bloqueado`.
        Token ruim ou vencido, conta anonimizada ou inexistente seguem como 401."""
        try:
            sub = str(self._decodificar(token)["sub"])
        except jwt.PyJWTError:
            return False
        perfil = self._usuarios.perfil(sub)
        return perfil is not None and perfil.status == "bloqueado"

    def conta_inativa(self, token: str) -> bool:
        """Token válido de conta com status `inativo` (Termos 4.9)."""
        try:
            sub = str(self._decodificar(token)["sub"])
        except jwt.PyJWTError:
            return False
        perfil = self._usuarios.perfil(sub)
        return perfil is not None and perfil.status == "inativo"

    def autenticar_para_suporte(self, token: str) -> Usuario | None:
        """Atendimento (Termos 20.5 e 4.9): conta bloqueada, suspensa ou inativa abre chamados
        e (quando inativa) pode reativar. Só conta que já existe; a anonimizada continua fora."""
        try:
            sub = str(self._decodificar(token)["sub"])
        except jwt.PyJWTError:
            return None
        perfil = self._usuarios.perfil(sub)
        if perfil is None or perfil.status not in (*STATUS_QUE_ENTRAM, "bloqueado", "inativo"):
            return None
        return Usuario(perfil.id, perfil.papel)

    def autenticar(self, token: str) -> Usuario | None:
        try:
            claims = self._decodificar(token)
        except jwt.PyJWTError:
            return None
        sub = str(claims["sub"])
        perfil = self._usuarios.perfil(sub)
        if perfil is None and self._criar_no_primeiro_login and not claims.get("is_anonymous"):
            # Primeiro login: cria a linha (cliente). O papel vem do banco; do token só o nome.
            meta = claims.get("user_metadata")
            nome = (
                (meta.get("nome") or meta.get("full_name") or meta.get("name"))
                if isinstance(meta, dict)
                else None
            )
            perfil = self._usuarios.garantir(sub, nome)
        if perfil is None or perfil.status not in STATUS_QUE_ENTRAM:
            return None
        return Usuario(perfil.id, perfil.papel)
