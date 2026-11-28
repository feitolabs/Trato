"""Rotas do app (cliente e profissional) para pedidos de informação adicional em disputas
(Termos 8.4)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api import disputa_pedidos_info as regras
from trato.api.auth import Usuario
from trato.api.contexto import (
    ContaBloqueada,
    Contexto,
    bloqueado_pode_no_pedido,
    obter_contexto,
    usuario_ou_bloqueado,
)
from trato.api.disputa_pedidos_info import PedidoInfoAppOut

router = APIRouter(prefix="/v1/disputas", tags=["disputas"])


class ResponderInfoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    resposta_texto: str = Field(min_length=1, max_length=2000)


def usuario_da_disputa(
    disputa_id: str,
    usuario: Usuario = Depends(usuario_ou_bloqueado),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Conta bloqueada só passa no próprio pedido contratado; fora dele (ou sem a disputa) a
    resposta é a de conta bloqueada, sem revelar se existe. É dependência para valer antes da
    validação do corpo."""
    if not usuario.bloqueado:
        return usuario
    try:
        _, _, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
    except HTTPException as erro:
        if erro.status_code == 404:
            raise ContaBloqueada from erro
        raise
    if not bloqueado_pode_no_pedido(pedido, usuario.id):
        raise ContaBloqueada
    return usuario


@router.get(
    "/{disputa_id}/pedidos-informacao",
    response_model=list[PedidoInfoAppOut],
    summary="Listar pedidos de informação adicional da disputa",
)
def listar_no_app(
    disputa_id: str,
    usuario: Usuario = Depends(usuario_da_disputa),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoInfoAppOut]:
    regras.exigir_tabela(contexto)
    did, _, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
    if usuario.id not in (pedido.cliente_id, pedido.profissional_id):
        raise HTTPException(403, "Só as partes do pedido podem ver os pedidos de informação.")
    itens = contexto.disputa_pedidos_info.listar_da_disputa(did)
    return [regras.saida_app(contexto, x, pedido.id) for x in itens]


@router.post(
    "/{disputa_id}/pedidos-informacao/{pedido_info_id}/responder",
    response_model=PedidoInfoAppOut,
    summary="Responder ao pedido de informação adicional da disputa",
)
def responder_no_app(
    disputa_id: str,
    pedido_info_id: str,
    corpo: ResponderInfoIn,
    usuario: Usuario = Depends(usuario_da_disputa),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoInfoAppOut:
    regras.exigir_tabela(contexto)
    with contexto.transacao():
        did, disputa, pedido = regras.resolver_disputa_e_pedido(contexto, disputa_id)
        item = contexto.disputa_pedidos_info.obter(pedido_info_id)
        if item is None or item.disputa_id != did:
            raise HTTPException(404, "Pedido de informação não encontrado.")
        esperado_id = (
            pedido.cliente_id if item.destinatario_papel == "cliente" else pedido.profissional_id
        )
        if usuario.id != esperado_id:
            raise HTTPException(
                403, "Apenas a parte solicitada pode responder a este pedido de informação."
            )
        if disputa.encerrada:
            raise HTTPException(409, "A disputa já está encerrada e não aceita mais respostas.")
        if item.respondido_em is not None:
            raise HTTPException(409, "Este pedido de informação já foi respondido.")
        if item.encerrado_sem_resposta_em is not None:
            raise HTTPException(409, "Este pedido de informação já foi encerrado sem resposta.")
        gravado = contexto.disputa_pedidos_info.responder(
            item.id, corpo.resposta_texto, contexto.agora()
        )
        if gravado is None:
            raise HTTPException(409, "Este pedido de informação não aceita mais resposta.")
    return regras.saida_app(contexto, gravado, pedido.id)
