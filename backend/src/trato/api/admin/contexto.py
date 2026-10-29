"""Contexto da API administrativa e a autorização por PAPEL da equipe.

O token só diz QUEM é o usuário. O papel é lido na tabela `equipe` a cada chamada (nada de papel
vindo do token), então papel revogado ou inativo é negado na hora.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request

from trato.api.admin.papeis import Permissao, pode
from trato.api.admin.repositorios import (
    AssinadorUrl,
    MembroEquipe,
    RepositorioAuditoriaAdmin,
    RepositorioConfigAdmin,
    RepositorioEquipe,
    RepositorioPedidosAdmin,
    RepositorioUsuariosAdmin,
    RepositorioVerificacoesAdmin,
)
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_atual

SEGUNDOS_URL_DOCUMENTO = 60  # URL assinada curta


@dataclass
class AdminContexto:
    equipe: RepositorioEquipe
    verificacoes: RepositorioVerificacoesAdmin
    usuarios: RepositorioUsuariosAdmin
    pedidos: RepositorioPedidosAdmin
    config: RepositorioConfigAdmin
    auditoria: RepositorioAuditoriaAdmin
    # Sem assinador, a URL do documento responde 503 (o bucket privado não é aberto às cegas).
    assinador: AssinadorUrl | None = None
    segundos_url: int = SEGUNDOS_URL_DOCUMENTO


@dataclass(frozen=True)
class Operador:
    """Quem está operando o painel: o usuário autenticado + a linha dele em `equipe`."""

    usuario: Usuario
    membro: MembroEquipe

    @property
    def id(self) -> str:
        return self.usuario.id


def obter_admin(request: Request, contexto: Contexto = Depends(obter_contexto)) -> AdminContexto:
    admin = getattr(request.app.state, "admin", None)
    if admin is None:
        banco = contexto.extras.get("banco")
        if banco is None:
            raise HTTPException(503, "API administrativa ainda sem os repositórios ligados.")
        from trato.api.admin.postgres import criar_admin_postgres

        admin = criar_admin_postgres(banco)
        request.app.state.admin = admin
    return admin


def exigir(*permissoes: Permissao) -> Callable[..., Operador]:
    """Dependência: o usuário precisa estar na equipe, vigente, com ao menos uma das permissões."""

    def dependencia(
        usuario: Usuario = Depends(usuario_atual),
        admin: AdminContexto = Depends(obter_admin),
    ) -> Operador:
        negado = HTTPException(403, "Seu papel na equipe não permite isso.")
        if usuario.papel is not PapelUsuario.EQUIPE:
            raise negado
        membro = admin.equipe.obter(usuario.id)
        if membro is None or not membro.vigente:
            raise negado
        if not any(pode(membro.papel, p) for p in permissoes):
            raise negado
        return Operador(usuario, membro)

    return dependencia
