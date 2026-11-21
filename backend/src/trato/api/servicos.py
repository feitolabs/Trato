"""Funções de apoio das rotas: acesso ao pedido e conversão para as saídas da API."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from fastapi import HTTPException, Request

from trato.api.acesso import auditar_consulta, operador_com
from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, papel_das_regras
from trato.api.modelos import JanelaOut, PedidoOut
from trato.pedidos.estados import Ator, Estado, Papel, Pedido, acoes_permitidas


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


def ator_de(usuario: Usuario, pedido: Pedido | None = None) -> Ator:
    if pedido is not None:
        if pedido.cliente_id == usuario.id:
            return Ator(Papel.CLIENTE, usuario.id)
        if pedido.profissional_id == usuario.id:
            return Ator(Papel.PROFISSIONAL, usuario.id)
    return Ator(papel_das_regras(usuario), usuario.id)


def nome_abreviado(nome: str | None) -> str | None:
    """'Gabriel Victor Lopes' -> 'Gabriel L.' (como o app mostra pessoas)."""
    partes = (nome or "").split()
    if not partes:
        return None
    return partes[0] if len(partes) == 1 else f"{partes[0]} {partes[-1][0]}."


def nomes_de_categorias(request: Any) -> dict[str, str]:
    """id e slug da categoria -> nome, do catálogo. Vazio se o catálogo não está disponível."""
    try:
        modulo = getattr(request.app.state, "modulo_profissional", None)
        if modulo is None:
            return {}
        nomes: dict[str, str] = {}
        for c in modulo.catalogo.categorias_publicas():
            nomes[str(c.id)] = c.nome
            nomes.setdefault(str(c.slug), c.nome)
        return nomes
    except Exception:  # noqa: BLE001 - campo opcional: sem o catálogo, vai sem o nome
        return {}


def _ja_avaliou(contexto: Contexto, pedido: Pedido, usuario: Usuario) -> bool:
    direcao = (
        "cliente_para_profissional"
        if pedido.cliente_id == usuario.id
        else "profissional_para_cliente"
    )
    try:
        return contexto.avaliacoes.obter(pedido.id, direcao) is not None
    except Exception:  # noqa: BLE001 - campo opcional
        return False


def pedido_out_completo(
    contexto: Contexto,
    pedido: Pedido,
    usuario: Usuario,
    ja_avaliou: bool = False,
    categorias: Mapping[str, str] | None = None,
) -> PedidoOut:
    """`pedido_out` mais o título do serviço, o nome da categoria e, para o profissional, o nome
    do cliente. `ja_avaliou` vale para quem consulta (lista e detalhe)."""
    if not ja_avaliou and pedido.estado is Estado.CONCLUIDO:
        ja_avaliou = _ja_avaliou(contexto, pedido, usuario)
    saida = pedido_out(pedido, usuario, ja_avaliou)
    try:
        dados = contexto.pedidos.dados_do_pedido(pedido.id)
    except Exception:  # noqa: BLE001 - sem os dados, o app mostra o número do pedido
        dados = None
    titulo = (dados.titulo or "").strip() if dados is not None else ""
    categoria_nome = (categorias or {}).get(str(dados.categoria_id)) if dados is not None else None
    cliente_nome = None
    profissional_nome = None
    if pedido.profissional_id == usuario.id and pedido.cliente_id != usuario.id:
        quem = contexto.usuarios.detalhe(pedido.cliente_id)
        cliente_nome = nome_abreviado(quem.nome) if quem is not None else None
    elif pedido.profissional_id is not None and pedido.cliente_id == usuario.id:
        quem = contexto.usuarios.detalhe(pedido.profissional_id)
        profissional_nome = nome_abreviado(quem.nome) if quem is not None else None
    contratado_em = None
    if pedido.profissional_id is not None:
        try:
            contrato = contexto.contratos.obter_do_pedido(pedido.id)
        except Exception:  # noqa: BLE001 - sem o contrato, a data só não aparece
            contrato = None
        contratado_em = contrato.aceito_em if contrato is not None else None
    return saida.model_copy(
        update={
            "titulo": titulo or None,
            "categoria_nome": categoria_nome,
            "urgente": bool(dados.urgente) if dados is not None else False,
            "cliente_nome": cliente_nome,
            "profissional_nome": profissional_nome,
            "contratado_em": contratado_em,
        }
    )


def pedido_out(pedido: Pedido, usuario: Usuario, ja_avaliou: bool = False) -> PedidoOut:
    eh_cliente = pedido.cliente_id == usuario.id
    papel_no_pedido = (
        Papel.CLIENTE
        if eh_cliente
        else (
            Papel.PROFISSIONAL
            if pedido.profissional_id == usuario.id
            else papel_das_regras(usuario)
        )
    )
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
        cliente_ausente_em=pedido.cliente_ausente_em,
        concluido_em=pedido.concluido_em,
        acoes_permitidas=sorted(a.value for a in acoes_permitidas(pedido, papel_no_pedido)),
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        codigo_inicio=pedido.codigo_inicio if eh_cliente else None,
        codigo_conclusao=pedido.codigo_conclusao if eh_cliente else None,
        modalidade="remoto" if pedido.remoto else "presencial",
        ja_avaliou=ja_avaliou,
        check_out_sem_codigo=pedido.check_out_sem_codigo,
    )
