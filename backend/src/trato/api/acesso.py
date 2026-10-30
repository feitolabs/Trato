"""Acesso da EQUIPE às rotas de uso do app (A2 da revisão de segurança).

O token só diz quem é. O que a pessoa da equipe pode ver vem da matriz de `api/admin/papeis.py`,
lida da tabela `equipe` a cada chamada. Qualquer falha (sem painel ligado, sem linha, papel
revogado, permissão que falta) é 403: na dúvida, nega.
"""

from __future__ import annotations

from fastapi import HTTPException, Request

from trato.api.admin.contexto import Operador, obter_admin
from trato.api.admin.papeis import Permissao, pode
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto

NEGADO = "Seu papel na equipe não permite isso."


def operador_com(
    request: Request, contexto: Contexto, usuario: Usuario, *permissoes: Permissao
) -> Operador:
    """A pessoa da equipe precisa estar vigente e ter ao menos uma das permissões."""
    if usuario.papel is not PapelUsuario.EQUIPE:
        raise HTTPException(403, NEGADO)
    try:
        admin = obter_admin(request, contexto)
    except HTTPException:
        raise HTTPException(403, NEGADO) from None
    membro = admin.equipe.obter(usuario.id)
    if membro is None or not membro.vigente or not any(pode(membro.papel, p) for p in permissoes):
        raise HTTPException(403, NEGADO)
    return Operador(usuario, membro)


def auditar_consulta(
    request: Request, contexto: Contexto, operador: Operador, pedido_id: str, o_que: str
) -> None:
    """Toda leitura de dado de pedido pela equipe fica registrada (quem, o quê, quando)."""
    admin = obter_admin(request, contexto)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="pedido.consulta_equipe",
        entidade="pedidos",
        entidade_id=pedido_id,
        depois={"consulta": o_que, "papel": operador.membro.papel.value},
    )
