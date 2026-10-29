"""Busca e detalhe de usuários e pedidos. Dado pessoal só com motivo e auditoria."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    ComMotivo,
    DadosPessoaisOut,
    EventoPedidoOut,
    Pagina,
    PedidoDetalheOut,
    PedidoResumoOut,
    PessoaOut,
    UsuarioOut,
)
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin", tags=["admin: usuários e pedidos"])


@router.get("/usuarios", response_model=Pagina[UsuarioOut], summary="Buscar usuários")
def buscar_usuarios(
    q: str | None = Query(None, min_length=2, max_length=100, description="Nome ou id."),
    status: str | None = Query(None, pattern="^(ativo|restrito|bloqueado|anonimizado)$"),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[UsuarioOut]:
    itens, total = admin.usuarios.buscar(q, status, limite, deslocamento)
    return Pagina(
        itens=[UsuarioOut.model_validate(u) for u in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/usuarios/{usuario_id}", response_model=UsuarioOut, summary="Detalhe (sem dados pessoais)"
)
def detalhe_usuario(
    usuario_id: str,
    _: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> UsuarioOut:
    achado = admin.usuarios.obter(usuario_id)
    if achado is None:
        raise HTTPException(404, "Usuário não encontrado.")
    return UsuarioOut.model_validate(achado)


@router.post(
    "/usuarios/{usuario_id}/dados-pessoais",
    response_model=DadosPessoaisOut,
    summary="Revelar dados pessoais (motivo obrigatório, vai para a auditoria)",
    description="É POST porque a leitura deixa rastro: `dado_pessoal.revelado` na auditoria.",
)
def revelar_dados_pessoais(
    usuario_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.DADOS_PESSOAIS_REVELAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> DadosPessoaisOut:
    dados = admin.usuarios.dados_pessoais(usuario_id, operador.id, corpo.motivo)
    if dados is None:
        raise HTTPException(404, "Usuário não encontrado.")
    return DadosPessoaisOut.model_validate(dados)


@router.get("/pedidos", response_model=Pagina[PedidoResumoOut], summary="Buscar pedidos")
def buscar_pedidos(
    q: str | None = Query(None, min_length=2, max_length=100, description="Título ou id."),
    estado: str | None = None,
    cliente_id: str | None = None,
    profissional_id: str | None = None,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.PEDIDOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[PedidoResumoOut]:
    itens, total = admin.pedidos.buscar(
        q, estado, cliente_id, profissional_id, limite, deslocamento
    )
    return Pagina(
        itens=[PedidoResumoOut.model_validate(p) for p in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/pedidos/{pedido_id}", response_model=PedidoDetalheOut, summary="Detalhe do pedido")
def detalhe_pedido(
    pedido_id: str,
    _: Operador = Depends(exigir(Permissao.PEDIDOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoDetalheOut:
    """Nunca devolve os códigos de início/conclusão nem o endereço."""
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    ids = [i for i in (pedido.cliente_id, pedido.profissional_id) if i]
    nomes = admin.usuarios.nomes(ids)
    return PedidoDetalheOut(
        id=pedido.id,
        estado=pedido.estado.value,
        cliente=PessoaOut(id=pedido.cliente_id, nome=nomes.get(pedido.cliente_id)),
        profissional=PessoaOut(
            id=pedido.profissional_id, nome=nomes.get(pedido.profissional_id or "")
        ),
        aberto_em=pedido.aberto_em,
        concluido_em=pedido.concluido_em,
        valor_contrato_centavos=contrato.valor_centavos if contrato else None,
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        tem_disputa=contexto.disputas.obter(pedido.id) is not None,
        eventos=[
            EventoPedidoOut(
                acao=e.acao.value,
                de=e.de.value,
                para=e.para.value,
                ator_papel=e.ator.papel.value,
                ator_id=e.ator.id,
                em=e.em,
            )
            for e in contexto.pedidos.eventos(pedido.id)
        ],
    )
