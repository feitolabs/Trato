"""Funções de apoio das rotas: acesso ao pedido e conversão para as saídas da API."""

from __future__ import annotations

from fastapi import HTTPException, Request

from trato.api.acesso import auditar_consulta, operador_com
from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, papel_das_regras
from trato.api.modelos import JanelaOut, PedidoOut
from trato.pedidos.estados import Ator, Pedido, acoes_permitidas


def eh_participante(pedido: Pedido, usuario: Usuario) -> bool:
    """Só cliente e profissional do pedido. A equipe NÃO é parte: ela passa pela matriz de
    permissões (`carregar_pedido(..., request=, equipe=)`), nunca por aqui."""
    return usuario.id in (pedido.cliente_id, pedido.profissional_id) and (
        usuario.papel is not PapelUsuario.EQUIPE
    )


def carregar_pedido(
    contexto: Contexto,
    pedido_id: str,
    usuario: Usuario,
    *,
    request: Request | None = None,
    equipe: tuple[Permissao, ...] = (),
    consulta: str = "pedido",
) -> Pedido:
    """Pedido de quem pode vê-lo. Quem não é parte recebe 404 (não revela que existe).

    A equipe só entra se a rota declarar `equipe=(Permissao...)` e a pessoa tiver uma delas;
    a leitura vai para a auditoria."""
    if usuario.papel is PapelUsuario.EQUIPE:
        if request is None or not equipe:
            raise HTTPException(403, "Seu papel na equipe não permite isso.")
        operador = operador_com(request, contexto, usuario, *equipe)
        pedido = contexto.pedidos.obter(pedido_id)
        if pedido is None:
            raise HTTPException(404, "Pedido não encontrado.")
        auditar_consulta(request, contexto, operador, pedido.id, consulta)
        return pedido
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
