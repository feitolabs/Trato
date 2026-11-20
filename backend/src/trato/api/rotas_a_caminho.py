"""Aviso "a caminho": o profissional avisa o cliente que saiu para o atendimento.

Só o profissional do pedido, com o pedido `agendado` (409 nos outros estados). Não muda o
estado do pedido nem mexe em falta, cancelamento ou dinheiro: só notifica o cliente. Repetir
dentro de 10 minutos não reenvia (200 com `enviado=false`).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt

from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_a_caminho
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.pedidos.estados import Estado

router = APIRouter(prefix="/v1", tags=["agenda"])

ETA_MINIMO, ETA_MAXIMO = 5, 180


class ACaminhoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    eta_minutos: StrictInt | None = Field(
        default=None,
        ge=ETA_MINIMO,
        le=ETA_MAXIMO,
        description="Chega em quantos minutos (5 a 180). Opcional.",
    )


class ACaminhoOut(BaseModel):
    pedido_id: str
    enviado: bool = Field(description="False: já houve aviso deste pedido nos últimos 10 minutos.")
    eta_minutos: int | None = None


@router.post(
    "/profissional/pedidos/{pedido_id}/a-caminho",
    response_model=ACaminhoOut,
    summary="Avisar o cliente que o profissional está a caminho",
)
def a_caminho(
    pedido_id: str,
    request: Request,
    corpo: ACaminhoIn | None = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ACaminhoOut:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or pedido.profissional_id != usuario.id:
        raise HTTPException(404, "Pedido não encontrado.")
    if pedido.estado is not Estado.AGENDADO:
        raise HTTPException(409, "Só dá para avisar que está a caminho num serviço agendado.")
    eta = corpo.eta_minutos if corpo is not None else None
    enviado = avisar_a_caminho(
        request,
        contexto,
        pedido_id=pedido.id,
        cliente_id=pedido.cliente_id,
        eta_minutos=eta,
        agora=contexto.agora(),
    )
    return ACaminhoOut(pedido_id=pedido.id, enviado=enviado, eta_minutos=eta)
