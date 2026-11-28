"""Rotas do app para solicitação de isenção por força maior (Termos 7.8 e 22.6)."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator

from trato.api import forca_maior as regras
from trato.api.auth import Usuario
from trato.api.contexto import (
    Contexto,
    obter_contexto,
    usuario_atual,
)
from trato.api.forca_maior import EventoForcaMaiorAppOut
from trato.pedidos.estados import Estado

router = APIRouter(prefix="/v1/pedidos", tags=["pedidos"])

_ESTADOS_NAO_ELEGIVEIS = frozenset({Estado.ABERTO, Estado.CONCLUIDO, Estado.CANCELADO})


class SolicitarForcaMaiorIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    acao_solicitada: Literal["reagendar", "cancelar"]
    descricao: str = Field(min_length=10, max_length=1000)
    comprovantes: list[str] = Field(default_factory=list, max_length=10)

    @field_validator("comprovantes")
    @classmethod
    def validar_comprovantes(cls, itens: list[str]) -> list[str]:
        limpos: list[str] = []
        for item in itens:
            texto = item.strip()
            if not texto or len(texto) > 500:
                raise ValueError("Cada comprovante precisa ter entre 1 e 500 caracteres.")
            limpos.append(texto)
        return limpos


@router.post(
    "/{pedido_id}/forca-maior",
    response_model=EventoForcaMaiorAppOut,
    status_code=201,
    summary="Solicitar isenção por evento externo / força maior (Termos 7.8 e 22.6)",
)
def solicitar_forca_maior(
    pedido_id: str,
    corpo: SolicitarForcaMaiorIn,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> EventoForcaMaiorAppOut:
    regras.exigir_tabela(contexto)
    with contexto.transacao():
        pedido = contexto.pedidos.obter(pedido_id)
        if pedido is None:
            raise HTTPException(404, "Pedido não encontrado.")
        if usuario.id == pedido.cliente_id:
            papel = "cliente"
        elif usuario.id == pedido.profissional_id:
            papel = "profissional"
        else:
            raise HTTPException(403, "Só as partes do pedido podem registrar força maior.")
        if pedido.estado in _ESTADOS_NAO_ELEGIVEIS:
            raise HTTPException(
                409, "Este pedido não está em um estado elegível para solicitação de força maior."
            )
        existentes = contexto.forca_maior.listar_do_pedido(pedido.id)
        if any(x.status == "pendente" for x in existentes):
            raise HTTPException(
                409, "Já existe uma solicitação de força maior pendente para este pedido."
            )
        criado = contexto.forca_maior.criar(
            pedido.id,
            usuario.id,
            papel,
            corpo.acao_solicitada,
            corpo.descricao,
            corpo.comprovantes,
            contexto.agora(),
        )
    return regras.saida_app(criado)


@router.get(
    "/{pedido_id}/forca-maior",
    response_model=list[EventoForcaMaiorAppOut],
    summary="Listar solicitações de força maior do pedido",
)
def listar_forca_maior_pedido(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[EventoForcaMaiorAppOut]:
    regras.exigir_tabela(contexto)
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if usuario.id not in (pedido.cliente_id, pedido.profissional_id):
        raise HTTPException(403, "Só as partes do pedido podem ver as solicitações de força maior.")
    return [regras.saida_app(x) for x in contexto.forca_maior.listar_do_pedido(pedido.id)]
