"""Reagendamento do serviço dentro do pedido: propor, listar, aceitar e recusar nova janela.

Só cliente e profissional do pedido (terceiro recebe 404). Vale com o pedido pago e ainda não
iniciado (`pago_e_retido` ou `agendado`). A outra parte aceita ou recusa; quem propôs não aceita
a própria proposta. Aceitar muda a janela do pedido pela MESMA transição da agenda (confirmar a
agenda ou remarcar), então códigos, ganchos e histórico seguem as regras de sempre.
"""

from __future__ import annotations

import logging
from dataclasses import replace
from datetime import datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.reagendamentos import PropostaPendente, Reagendamento
from trato.api.servicos import ator_de, carregar_pedido
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados as pedidos_estados
from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Janela,
    Papel,
    ProvaAgenda,
    ProvaRemarcacao,
    TransicaoInvalida,
)
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_texto

log = logging.getLogger(__name__)
router = APIRouter(prefix="/v1", tags=["agenda"])

ESTADOS_QUE_REAGENDAM = (Estado.PAGO_E_RETIDO, Estado.AGENDADO)
_NAO_PODE = "Este pedido não pode ser reagendado no momento."
# Limites de abuso (a janela nova é de até 60 dias à frente; 5 propostas por pedido a cada 24 h).
MAX_DIAS_A_FRENTE = 60
MAX_PROPOSTAS_POR_DIA = 5
_JA_RESPONDIDO = "Este pedido de reagendamento já foi respondido."


class ReagendamentoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nova_janela_inicio: datetime
    nova_janela_fim: datetime
    motivo: str | None = Field(default=None, max_length=500)


class ReagendamentoOut(BaseModel):
    id: str
    pedido_id: str
    proposto_por: str
    nova_janela_inicio: datetime
    nova_janela_fim: datetime
    motivo: str
    status: str = Field(description="pendente, aceito, recusado ou cancelado.")
    respondido_por: str | None = None
    respondido_em: datetime | None = None
    criado_em: datetime


def _out(r: Reagendamento) -> ReagendamentoOut:
    return ReagendamentoOut(**r.__dict__)


def _avisar(
    request: Request, contexto: Contexto, evento: Evento, destino: str | None, **dados: Any
) -> None:
    """Aviso é secundário: sem notificador ou com falha, a rota segue."""
    if not destino:
        return
    try:
        from trato.api.avisos import servicos_de_notificacao

        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(evento, destino, **dados)
    except Exception:  # noqa: BLE001
        log.warning("aviso de reagendamento não enviado", exc_info=True)


# Pedido pago e ainda SEM horário (`pago_e_retido`): é o primeiro agendamento, não um
# reagendamento. Os avisos precisam dizer isso (o pedido aparece como "agendado").
_TEXTOS_PRIMEIRO = {
    "proposto": (
        "Horário proposto para o serviço",
        "A outra parte propôs um horário para o serviço. Responda no pedido.",
    ),
    "aceito": ("Serviço agendado", "O horário foi aceito: o serviço está agendado."),
    "recusado": (
        "Horário não confirmado",
        "O horário proposto foi recusado. Combinem outro: ainda não há horário marcado.",
    ),
    "cancelado": (
        "Horário não confirmado",
        "A proposta de horário foi cancelada. Ainda não há horário marcado.",
    ),
}
_TEXTOS_REMARCAR = {
    "proposto": (None, None),  # os textos padrão do evento já falam em novo horário
    "aceito": (
        "Reagendamento aceito",
        "O novo horário do serviço foi aceito. Veja os detalhes no pedido.",
    ),
    "recusado": (
        None,
        "O novo horário foi recusado. O horário combinado continua o mesmo.",
    ),
    "cancelado": (
        None,
        "O pedido de reagendamento foi cancelado. O horário combinado continua o mesmo.",
    ),
}


def _textos(pedido: Any, situacao: str) -> dict[str, str]:
    primeiro = pedido.estado is Estado.PAGO_E_RETIDO
    titulo, corpo = (_TEXTOS_PRIMEIRO if primeiro else _TEXTOS_REMARCAR)[situacao]
    extras = {"titulo": titulo, "corpo": corpo}
    return {k: v for k, v in extras.items() if v is not None}


def _outra_parte(pedido: Any, usuario_id: str) -> str | None:
    return pedido.profissional_id if usuario_id == pedido.cliente_id else pedido.cliente_id


def _carregar(contexto: Contexto, pedido: Any, reagendamento_id: str) -> Reagendamento:
    r = contexto.reagendamentos.obter(reagendamento_id)
    if r is None or r.pedido_id != pedido.id:
        raise HTTPException(404, "Pedido de reagendamento não encontrado.")
    return r


@router.post(
    "/pedidos/{pedido_id}/reagendamentos",
    response_model=ReagendamentoOut,
    status_code=201,
    summary="Propor uma nova janela de atendimento",
)
def propor_reagendamento(
    pedido_id: str,
    corpo: ReagendamentoIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ReagendamentoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado not in ESTADOS_QUE_REAGENDAM or not pedido.profissional_id:
        raise HTTPException(409, _NAO_PODE)
    agora = contexto.agora()
    if corpo.nova_janela_fim <= corpo.nova_janela_inicio:
        raise HTTPException(422, "A nova janela precisa terminar depois de começar.")
    if corpo.nova_janela_inicio <= agora:
        raise HTTPException(422, "A nova janela precisa começar no futuro.")
    if corpo.nova_janela_inicio > agora + timedelta(days=MAX_DIAS_A_FRENTE):
        raise HTTPException(
            422, f"A nova janela pode ser no máximo {MAX_DIAS_A_FRENTE} dias à frente."
        )
    desde = agora - timedelta(hours=24)
    if contexto.reagendamentos.contar_propostas(pedido.id, desde) >= MAX_PROPOSTAS_POR_DIA:
        raise HTTPException(
            429,
            "Este pedido já teve muitos pedidos de reagendamento hoje. Tente de novo amanhã.",
        )
    motivo = limpar_texto(corpo.motivo or "", "motivo", 500, obter_config_seguranca())
    try:
        nova = contexto.reagendamentos.propor(
            pedido.id, usuario.id, corpo.nova_janela_inicio, corpo.nova_janela_fim, motivo, agora
        )
    except PropostaPendente:
        raise HTTPException(
            409, "Já existe um pedido de reagendamento aguardando resposta."
        ) from None
    _avisar(
        request,
        contexto,
        Evento.REAGENDAMENTO_PROPOSTO,
        _outra_parte(pedido, usuario.id),
        chave=f"reagendamento:{nova.id}:proposto",
        pedido_id=pedido.id,
        **_textos(pedido, "proposto"),
    )
    return _out(nova)


@router.get(
    "/pedidos/{pedido_id}/reagendamentos",
    response_model=list[ReagendamentoOut],
    summary="Listar os pedidos de reagendamento (mais recentes primeiro)",
)
def listar_reagendamentos(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ReagendamentoOut]:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    return [_out(r) for r in contexto.reagendamentos.listar(pedido.id)]


@router.post(
    "/pedidos/{pedido_id}/reagendamentos/{reagendamento_id}/aceitar",
    response_model=ReagendamentoOut,
    summary="Aceitar o reagendamento (só a outra parte): a janela do pedido muda",
)
def aceitar_reagendamento(
    pedido_id: str,
    reagendamento_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ReagendamentoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    r = _carregar(contexto, pedido, reagendamento_id)
    if r.proposto_por == usuario.id:
        raise HTTPException(403, "Apenas a outra parte pode aceitar o reagendamento.")
    if r.status != "pendente":
        raise HTTPException(409, _JA_RESPONDIDO)
    if pedido.estado not in ESTADOS_QUE_REAGENDAM or not pedido.profissional_id:
        raise HTTPException(409, _NAO_PODE)
    agora = contexto.agora()
    janela = Janela(r.nova_janela_inicio, r.nova_janela_fim)
    prazos = contexto.config.carregar().prazos_pedido
    try:
        if pedido.estado is Estado.PAGO_E_RETIDO:
            transicao = pedidos_estados.transicionar(
                pedido,
                Acao.CONFIRMAR_AGENDA,
                Ator(Papel.PROFISSIONAL, pedido.profissional_id),
                agora,
                ProvaAgenda(janela),
                prazos,
            )
        else:
            transicao = pedidos_estados.transicionar(
                pedido,
                Acao.REMARCAR,
                ator_de(usuario, pedido),
                agora,
                ProvaRemarcacao(janela, r.proposto_por),
                prazos,
            )
    except TransicaoInvalida as erro:
        raise HTTPException(422, str(erro)) from None
    with contexto.transacao():
        respondido = contexto.reagendamentos.responder(r.id, "aceito", usuario.id, agora)
        if respondido is None:
            raise HTTPException(409, _JA_RESPONDIDO)
        # O histórico do pedido registra quem de fato aceitou (a regra da agenda exige o
        # profissional na transição, mas a pessoa que respondeu pode ser o cliente).
        evento = replace(transicao.evento, ator=ator_de(usuario, pedido))
        gravado = contexto.pedidos.salvar(transicao.pedido, evento)
        for gancho in contexto.apos_transicao:
            gancho(pedido, gravado, evento.acao, contexto)
    _avisar(
        request,
        contexto,
        Evento.REAGENDAMENTO_RESPONDIDO,
        r.proposto_por,
        chave=f"reagendamento:{r.id}:aceito",
        pedido_id=pedido.id,
        **_textos(pedido, "aceito"),
    )
    return _out(respondido)


@router.post(
    "/pedidos/{pedido_id}/reagendamentos/{reagendamento_id}/recusar",
    response_model=ReagendamentoOut,
    summary="Recusar o reagendamento (a outra parte) ou cancelá-lo (quem propôs)",
)
def recusar_reagendamento(
    pedido_id: str,
    reagendamento_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ReagendamentoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    r = _carregar(contexto, pedido, reagendamento_id)
    if r.status != "pendente":
        raise HTTPException(409, _JA_RESPONDIDO)
    cancelando = r.proposto_por == usuario.id
    respondido = contexto.reagendamentos.responder(
        r.id, "cancelado" if cancelando else "recusado", usuario.id, contexto.agora()
    )
    if respondido is None:
        raise HTTPException(409, _JA_RESPONDIDO)
    _avisar(
        request,
        contexto,
        Evento.REAGENDAMENTO_RESPONDIDO,
        _outra_parte(pedido, usuario.id),
        chave=f"reagendamento:{r.id}:{respondido.status}",
        pedido_id=pedido.id,
        **_textos(pedido, "cancelado" if cancelando else "recusado"),
    )
    return _out(respondido)
