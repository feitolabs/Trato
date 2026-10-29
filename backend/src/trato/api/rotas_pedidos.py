"""Rotas do pedido: criar, consultar, mudar de estado, disputa e retrabalho.

Nenhuma regra mora aqui: `pedidos/estados.py`, `disputas/` e `garantias/` decidem; a rota
identifica quem pede, monta a prova, chama a regra e grava o resultado.
"""

from __future__ import annotations

import uuid
from dataclasses import replace
from datetime import timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel, ValidationError

from trato import disputas
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.modelos import (
    AbrirDisputaIn,
    AcaoPedidoIn,
    AceitarOrcamentoIn,
    CancelarIn,
    CheckInIn,
    CheckOutIn,
    ConfirmarAgendaIn,
    DisputaOut,
    EventoOut,
    PedidoOut,
    PedirRetrabalhoIn,
    RetrabalhoOut,
)
from trato.api.repositorios import Contrato
from trato.api.servicos import ator_de, carregar_pedido, pedido_out
from trato.garantias import abrir_garantia, abrir_retrabalho
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Estado, Papel, Pedido, Prova, ProvaDisputa, ProvaRetrabalho

router = APIRouter(prefix="/v1/pedidos", tags=["pedidos"])

_ROTA_DEDICADA = {
    Acao.ABRIR_DISPUTA: "POST /v1/pedidos/{id}/disputa",
    Acao.PEDIR_RETRABALHO: "POST /v1/pedidos/{id}/retrabalho",
}
# Pontos de extensão: dependem de fluxos que ainda não existem (ver README da API).
_NAO_DISPONIVEIS = {
    Acao.REMARCAR: "A remarcação depende do registro do aceite da outra parte (a definir).",
    Acao.DECIDIR_DISPUTA: "A decisão da disputa depende de definir como ela move o dinheiro "
    "(P4/P8).",
}


def _so_sistema(acao: Acao) -> bool:
    return set(estados.REGRAS[acao].quem) == {Papel.SISTEMA}


def _validar(modelo: type[BaseModel], bruto: dict[str, Any] | None) -> Any:
    try:
        return modelo.model_validate(bruto or {})
    except ValidationError as erro:
        raise RequestValidationError(
            erro.errors(include_url=False, include_context=False)
        ) from erro


def _montar_prova(
    contexto: Contexto, acao: Acao, bruto: dict[str, Any] | None, pedido: Pedido
) -> Prova | None:
    if acao is Acao.ACEITAR_ORCAMENTO:
        entrada: AceitarOrcamentoIn = _validar(AceitarOrcamentoIn, bruto)
        orcamento = contexto.orcamentos.obter(entrada.orcamento_id)
        if orcamento is None or orcamento.pedido_id != pedido.id:
            raise estados.ProvaInvalida("Esse orçamento não existe neste pedido.")
        return entrada.para_regra(orcamento.profissional_id)
    por_acao = {
        Acao.CONFIRMAR_AGENDA: ConfirmarAgendaIn,
        Acao.FAZER_CHECK_IN: CheckInIn,
        Acao.FAZER_CHECK_OUT: CheckOutIn,
        Acao.CANCELAR: CancelarIn,
    }
    modelo = por_acao.get(acao)
    if modelo is None:
        if bruto:
            raise estados.ProvaInvalida(f"Para {estados.REGRAS[acao].rotulo} não se envia prova.")
        return None
    return _validar(modelo, bruto).para_regra()


def _concluir_efeitos(contexto: Contexto, pedido: Pedido) -> None:
    """Ao concluir pela primeira vez, abre a garantia (dias congelados pela configuração)."""
    if pedido.estado is not Estado.CONCLUIDO or pedido.concluido_em is None:
        return
    if contexto.garantias.obter_garantia(pedido.id) is not None:
        return
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    categoria = contrato.categoria_id if contrato else None
    garantia = abrir_garantia(pedido.concluido_em, categoria, contexto.config.carregar().garantias)
    contexto.garantias.salvar_garantia(pedido.id, garantia)


@router.post("", response_model=PedidoOut, status_code=201, summary="Abrir pedido")
def abrir_pedido(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoOut:
    pedido = estados.abrir_pedido(uuid.uuid4().hex, ator_de(usuario), contexto.agora())
    contexto.pedidos.salvar(pedido)
    return pedido_out(pedido, usuario)


@router.get("", response_model=list[PedidoOut], summary="Meus pedidos")
def listar_pedidos(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[PedidoOut]:
    como_cliente = usuario.papel is PapelUsuario.CLIENTE
    achados = contexto.pedidos.listar_do_usuario(usuario.id, como_cliente)
    return [pedido_out(p, usuario) for p in achados]


@router.get("/{pedido_id}", response_model=PedidoOut, summary="Ver pedido")
def ver_pedido(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoOut:
    return pedido_out(carregar_pedido(contexto, pedido_id, usuario), usuario)


@router.get("/{pedido_id}/eventos", response_model=list[EventoOut], summary="Histórico do pedido")
def ver_eventos(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[EventoOut]:
    carregar_pedido(contexto, pedido_id, usuario)
    return [
        EventoOut(
            acao=e.acao.value,
            de=e.de.value,
            para=e.para.value,
            ator_papel=e.ator.papel.value,
            ator_id=e.ator.id,
            em=e.em,
        )
        for e in contexto.pedidos.eventos(pedido_id)
    ]


@router.post(
    "/{pedido_id}/acoes/{acao}",
    response_model=PedidoOut,
    summary="Mudar o estado do pedido",
    description=(
        "Valida quem pode (papel e pessoa), quando (estado e prazo) e com qual prova, usando "
        "`pedidos/estados.py`. Ações do sistema (expirar, confirmar pagamento, ausência, "
        "concluir por prazo) não passam por aqui. Disputa e retrabalho têm rota própria."
    ),
)
def mudar_estado(
    pedido_id: str,
    acao: Acao,
    corpo: AcaoPedidoIn | None = None,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if _so_sistema(acao):
        raise HTTPException(403, "Esta ação é feita só pelo sistema.")
    if acao in _ROTA_DEDICADA:
        raise HTTPException(400, f"Use a rota {_ROTA_DEDICADA[acao]}.")
    if acao in _NAO_DISPONIVEIS:
        raise HTTPException(501, _NAO_DISPONIVEIS[acao])

    prova = _montar_prova(contexto, acao, corpo.prova if corpo else None, pedido)
    cfg = contexto.config.carregar()
    transicao = estados.transicionar(
        pedido, acao, ator_de(usuario), contexto.agora(), prova, cfg.prazos_pedido
    )
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)

    if acao is Acao.ACEITAR_ORCAMENTO:
        orcamento = contexto.orcamentos.obter(transicao.pedido.orcamento_id or "")
        if orcamento is not None:
            contexto.contratos.salvar(
                Contrato(
                    pedido.id,
                    orcamento.id,
                    orcamento.profissional_id,
                    orcamento.valor_centavos,
                    orcamento.categoria_id,
                )
            )
    _concluir_efeitos(contexto, transicao.pedido)
    for gancho in contexto.apos_transicao:
        gancho(pedido, transicao.pedido, acao, contexto)
    return pedido_out(transicao.pedido, usuario)


# --- Disputa ----------------------------------------------------------------------------


def _disputa_out(pedido_id: str, d: disputas.Disputa) -> DisputaOut:
    return DisputaOut(
        pedido_id=pedido_id,
        estado=d.estado.value,
        motivo=d.motivo.value,
        valor_congelado_centavos=d.valor_congelado,
        aberta_em=d.aberta_em,
        resposta_ate=d.prazos.resposta_ate,
        decisao_ate=d.prazos.decisao_ate,
        respondida_em=d.respondida_em,
        sem_resposta=d.sem_resposta,
    )


@router.post(
    "/{pedido_id}/disputa",
    response_model=DisputaOut,
    status_code=201,
    summary="Abrir disputa",
    description=(
        "Só o cliente. O valor congelado é o que o ledger mostra como retido + a liberar "
        "no pedido (o app não envia valor)."
    ),
)
def abrir_disputa(
    pedido_id: str,
    corpo: AbrirDisputaIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    agora = contexto.agora()
    prova = ProvaDisputa(corpo.motivo, corpo.descricao, tuple(f.para_regra() for f in corpo.fotos))
    transicao = estados.transicionar(pedido, Acao.ABRIR_DISPUTA, ator_de(usuario), agora, prova)

    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    congelado = saldo.retido + saldo.a_liberar
    if congelado <= 0:
        raise HTTPException(409, "Não há valor retido neste pedido para congelar.")
    disputa = disputas.abrir(
        disputas.Ator.CLIENTE,
        congelado,
        disputas.Motivo(corpo.motivo.value),
        pedido.concluido_em or agora,
        agora,
        contexto.config.carregar().disputas,
    )
    contexto.disputas.salvar(pedido.id, disputa)
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    return _disputa_out(pedido.id, disputa)


@router.get("/{pedido_id}/disputa", response_model=DisputaOut, summary="Ver disputa")
def ver_disputa(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaOut:
    carregar_pedido(contexto, pedido_id, usuario)
    disputa = contexto.disputas.obter(pedido_id)
    if disputa is None:
        raise HTTPException(404, "Este pedido não tem disputa.")
    return _disputa_out(pedido_id, disputa)


@router.post(
    "/{pedido_id}/disputa/resposta",
    response_model=DisputaOut,
    summary="Profissional responde a disputa",
)
def responder_disputa(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional contratado neste pedido pode responder.")
    disputa = contexto.disputas.obter(pedido_id)
    if disputa is None:
        raise HTTPException(404, "Este pedido não tem disputa.")
    nova = disputa.responder(disputas.Ator.PROFISSIONAL, contexto.agora())
    contexto.disputas.salvar(pedido_id, nova)
    return _disputa_out(pedido_id, nova)


# --- Retrabalho -------------------------------------------------------------------------


@router.post(
    "/{pedido_id}/retrabalho",
    response_model=RetrabalhoOut,
    status_code=201,
    summary="Pedir retrabalho (suporte e análise de problemas)",
)
def pedir_retrabalho(
    pedido_id: str,
    corpo: PedirRetrabalhoIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE)),
    contexto: Contexto = Depends(obter_contexto),
) -> RetrabalhoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    agora = contexto.agora()
    cfg = contexto.config.carregar()

    garantia = contexto.garantias.obter_garantia(pedido.id)
    if garantia is None and pedido.concluido_em is not None:
        contrato = contexto.contratos.obter_do_pedido(pedido.id)
        categoria = contrato.categoria_id if contrato else None
        garantia = abrir_garantia(pedido.concluido_em, categoria, cfg.garantias)
    prazos = cfg.prazos_pedido
    if garantia is not None:
        prazos = replace(prazos, garantia=timedelta(days=garantia.dias))

    prova = ProvaRetrabalho(corpo.descricao, tuple(f.para_regra() for f in corpo.fotos))
    transicao = estados.transicionar(
        pedido, Acao.PEDIR_RETRABALHO, ator_de(usuario), agora, prova, prazos
    )
    if garantia is None:  # transicionar já recusa pedido sem conclusão; defesa extra
        raise HTTPException(409, "Este pedido ainda não tem garantia.")
    retrabalho = abrir_retrabalho(
        garantia, corpo.descricao, agora, cfg.garantias, contexto.garantias.retrabalhos(pedido.id)
    )
    contexto.garantias.salvar_garantia(pedido.id, garantia)
    contexto.garantias.salvar_retrabalho(pedido.id, retrabalho)
    contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    return RetrabalhoOut(
        pedido_id=pedido.id,
        estado=retrabalho.estado.value,
        aberto_em=retrabalho.aberto_em,
        atender_ate=retrabalho.atender_ate,
        descricao=retrabalho.descricao,
    )
