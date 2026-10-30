"""Consulta de saldo e extrato. Tudo sai do ledger (nada é guardado); o app só mostra."""

from __future__ import annotations

from collections.abc import Sequence

from fastapi import APIRouter, Depends, Query, Request

from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.modelos import (
    ContaOut,
    ExtratoOut,
    LancamentoOut,
    SaldoPedidoOut,
    SaldoProfissionalOut,
)
from trato.api.servicos import carregar_pedido
from trato.financeiro.ledger import Conta, Lancamento, a_liberar, liberado

router = APIRouter(prefix="/v1", tags=["financeiro"])

LIMITE_MAXIMO = 100


def _conta_out(conta: Conta) -> ContaOut:
    return ContaOut(tipo=conta.tipo.value, titular=conta.titular)


def _lancamento_out(item: Lancamento) -> LancamentoOut:
    return LancamentoOut(
        id=item.id,
        pedido_id=item.pedido_id,
        tipo=item.tipo.value,
        valor_centavos=item.valor,
        data=item.data,
        debito=_conta_out(item.debito),
        credito=_conta_out(item.credito),
        estorno_de=item.estorno_de,
    )


def _extrato(itens: Sequence[Lancamento], limite: int, deslocamento: int) -> ExtratoOut:
    """Mais novos primeiro (empate de data: o gravado por último vem antes)."""
    ordem = sorted(enumerate(itens), key=lambda par: (par[1].data, par[0]), reverse=True)
    pagina = [_lancamento_out(i) for _, i in ordem[deslocamento : deslocamento + limite]]
    return ExtratoOut(itens=pagina, total=len(itens), limite=limite, deslocamento=deslocamento)


@router.get(
    "/pedidos/{pedido_id}/saldo",
    response_model=SaldoPedidoOut,
    summary="Saldo do pedido (retido, a liberar, liberado, taxa)",
)
def saldo_do_pedido(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> SaldoPedidoOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="saldo",
    )
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    return SaldoPedidoOut(
        pedido_id=pedido.id,
        cliente_pagou_centavos=saldo.cliente_pagou,
        retido_centavos=saldo.retido,
        a_liberar_centavos=saldo.a_liberar,
        liberado_centavos=saldo.liberado,
        taxa_trato_centavos=saldo.taxa_trato,
    )


@router.get(
    "/pedidos/{pedido_id}/extrato", response_model=ExtratoOut, summary="Lançamentos do pedido"
)
def extrato_do_pedido(
    pedido_id: str,
    request: Request,
    limite: int = Query(20, ge=1, le=LIMITE_MAXIMO),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="extrato",
    )
    return _extrato(contexto.ledger.lancamentos(pedido.id), limite, deslocamento)


@router.get(
    "/profissionais/me/saldo",
    response_model=SaldoProfissionalOut,
    summary="Carteira do profissional (a liberar e liberado)",
)
def saldo_do_profissional(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> SaldoProfissionalOut:
    return SaldoProfissionalOut(
        a_liberar_centavos=contexto.ledger.saldo_da_conta(a_liberar(usuario.id)),
        liberado_centavos=contexto.ledger.saldo_da_conta(liberado(usuario.id)),
    )


@router.get(
    "/extrato",
    response_model=ExtratoOut,
    summary="Meu extrato",
    description=(
        "Profissional: lançamentos nas contas dele. Cliente: lançamentos dos pedidos dele."
    ),
)
def meu_extrato(
    limite: int = Query(20, ge=1, le=LIMITE_MAXIMO),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoOut:
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        minhas = {a_liberar(usuario.id), liberado(usuario.id)}
        itens = [
            i for i in contexto.ledger.lancamentos() if i.debito in minhas or i.credito in minhas
        ]
    else:
        pedidos = {p.id for p in contexto.pedidos.listar_do_usuario(usuario.id, True)}
        itens = [i for i in contexto.ledger.lancamentos() if i.pedido_id in pedidos]
    return _extrato(itens, limite, deslocamento)
