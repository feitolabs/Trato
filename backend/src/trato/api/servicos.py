"""Funções de apoio das rotas: acesso ao pedido e conversão para as saídas da API."""

from __future__ import annotations

from fastapi import HTTPException

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, papel_das_regras
from trato.api.modelos import JanelaOut, PedidoOut
from trato.pedidos.estados import Ator, Pedido, acoes_permitidas


def eh_participante(pedido: Pedido, usuario: Usuario) -> bool:
    if usuario.papel is PapelUsuario.EQUIPE:
        return True
    return usuario.id in (pedido.cliente_id, pedido.profissional_id)


def carregar_pedido(contexto: Contexto, pedido_id: str, usuario: Usuario) -> Pedido:
    """Pedido de quem pode vê-lo. Quem não é parte recebe 404 (não revela que existe)."""
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or not eh_participante(pedido, usuario):
        raise HTTPException(404, "Pedido não encontrado.")
    return pedido


def ator_de(usuario: Usuario) -> Ator:
    return Ator(papel_das_regras(usuario), usuario.id)


def pedido_out(pedido: Pedido, usuario: Usuario) -> PedidoOut:
    eh_cliente = usuario.papel is PapelUsuario.CLIENTE
    return PedidoOut(
        id=pedido.id,
        estado=pedido.estado.value,
        estado_nome=pedido.estado.nome,
        cliente_id=pedido.cliente_id,
        profissional_id=pedido.profissional_id,
        aberto_em=pedido.aberto_em,
        janela=JanelaOut(inicio=pedido.janela.inicio, fim=pedido.janela.fim)
        if pedido.janela
        else None,
        concluido_em=pedido.concluido_em,
        acoes_permitidas=sorted(
            a.value for a in acoes_permitidas(pedido, papel_das_regras(usuario))
        ),
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        codigo_inicio=pedido.codigo_inicio if eh_cliente else None,
        codigo_conclusao=pedido.codigo_conclusao if eh_cliente else None,
    )
