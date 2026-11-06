"""Busca e detalhe de usuários e pedidos. Dado pessoal só com motivo e auditoria."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    CategoriaProfissionalOut,
    ComMotivo,
    DadosPessoaisOut,
    DiagnosticoOut,
    EuOut,
    EventoPedidoOut,
    EventoUsuarioOut,
    ItemDiagnosticoOut,
    Pagina,
    PedidoDetalheOut,
    PedidoResumoOut,
    PessoaOut,
    UsuarioDetalheOut,
    UsuarioOut,
)
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin", tags=["admin: usuários e pedidos"])


@router.get("/eu", response_model=EuOut, summary="Quem sou eu (papel e alçada no painel)")
def eu(
    operador: Operador = Depends(exigir()),
    admin: AdminContexto = Depends(obter_admin),
) -> EuOut:
    conhecido = admin.usuarios.obter(operador.id)
    # Já vem limitada ao teto do papel (RP-02). Quem não tem alçada mostra "Sem alçada financeira".
    alcada = operador.membro.alcada_centavos or 0
    return EuOut(
        id=operador.id,
        papel=operador.membro.papel.value,
        nome=conhecido.nome if conhecido else None,
        alcada_centavos=alcada,
    )


def _usuario_out(u: object, extras: dict) -> UsuarioOut:
    saida = UsuarioOut.model_validate(u)
    c = extras.get(saida.id)
    if c is not None:
        saida.publico_id = c.publico_id
        saida.email_mascarado = c.email_mascarado
        saida.telefone_mascarado = c.telefone_mascarado
        saida.cidade = c.cidade
    return saida


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
    extras = admin.usuarios.complementos(itens)
    return Pagina(
        itens=[_usuario_out(u, extras) for u in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/usuarios/{usuario_id}",
    response_model=UsuarioDetalheOut,
    summary="Detalhe (contato mascarado, categorias e histórico)",
)
def detalhe_usuario(
    usuario_id: str,
    _: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> UsuarioDetalheOut:
    achado = admin.usuarios.obter(usuario_id)
    if achado is None:
        raise HTTPException(404, "Usuário não encontrado.")
    base = _usuario_out(achado, admin.usuarios.complementos([achado]))
    return UsuarioDetalheOut(
        **base.model_dump(),
        categorias=[
            CategoriaProfissionalOut(
                categoria_id=c.categoria_id,
                nome=c.nome,
                ativa_no_perfil=c.ativa_no_perfil,
                ativa_na_plataforma=c.ativa_na_plataforma,
            )
            for c in admin.usuarios.categorias(usuario_id)
        ],
        historico=[
            EventoUsuarioOut(em=e.em, texto=e.texto)
            for e in admin.usuarios.historico(usuario_id, 20)
        ],
    )


@router.get(
    "/usuarios/{usuario_id}/diagnostico-pedido",
    response_model=DiagnosticoOut,
    summary="Por que este pedido não aparece para este profissional? (RN-01)",
)
def diagnostico_pedido(
    usuario_id: str,
    pedido: str = Query(..., min_length=2, max_length=60, description="Código PED-10482 ou id."),
    _: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> DiagnosticoOut:
    if admin.usuarios.obter(usuario_id) is None:
        raise HTTPException(404, "Usuário não encontrado.")
    d = admin.usuarios.diagnosticar(usuario_id, pedido)
    if d is None:
        raise HTTPException(404, "Pedido não encontrado.")
    return DiagnosticoOut(
        pedido_id=d.pedido_id,
        pedido_numero=d.pedido_numero,
        pedido_titulo=d.pedido_titulo,
        categoria=d.categoria,
        aparece=d.aparece,
        itens=[ItemDiagnosticoOut(ok=i.ok, titulo=i.titulo, detalhe=i.detalhe) for i in d.itens],
    )


class AlterarStatusUsuarioIn(BaseModel):
    status: str = Field(pattern="^(ativo|restrito|bloqueado)$")
    motivo: str = Field(min_length=10, max_length=500)


@router.post(
    "/usuarios/{usuario_id}/status",
    response_model=UsuarioOut,
    summary="Alterar status do usuário (ativo, restrito, bloqueado)",
)
def alterar_status_usuario(
    usuario_id: str,
    corpo: AlterarStatusUsuarioIn,
    operador: Operador = Depends(exigir(Permissao.USUARIOS_STATUS)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> UsuarioOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")
    with banco.transacao() as con:
        usuario = con.execute(
            "SELECT id, nome, status FROM public.usuarios WHERE id = %s", (uid,)
        ).fetchone()
        if usuario is None:
            raise HTTPException(404, "Usuário não encontrado.")
        con.execute(
            "UPDATE public.usuarios SET status = %s, atualizado_em = now() WHERE id = %s",
            (corpo.status, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="usuario.status_alterado",
            entidade="usuarios",
            entidade_id=str(uid),
            depois={"status": corpo.status, "nome": usuario["nome"]},
            motivo=corpo.motivo,
        )
    achado = admin.usuarios.obter(usuario_id)
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
