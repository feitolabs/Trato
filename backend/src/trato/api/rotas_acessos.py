"""O login e o logout acontecem no app (provedor de login): ele avisa aqui (Termos 14.3)."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.acessos import registrar
from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_do_suporte

router = APIRouter(prefix="/v1/me/acessos", tags=["acessos"])


class EventoDeAcessoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    evento: Literal["login", "sessao_renovada", "logout"]


class EventoDeAcessoOut(BaseModel):
    registrado: bool = Field(description="false: não gravou; o app segue normalmente.")


@router.post("", response_model=EventoDeAcessoOut, summary="Avisar login, renovação ou saída")
def avisar_evento_de_acesso(
    corpo: EventoDeAcessoIn,
    request: Request,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
) -> EventoDeAcessoOut:
    resultado = registrar(request, contexto, usuario.id, corpo.evento)
    return EventoDeAcessoOut(registrado=resultado == "registrado")
