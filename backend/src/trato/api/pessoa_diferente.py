"""Termos 9.5: chegou uma pessoa diferente da verificada. O cliente relata e o Trato cancela o
pedido com reembolso integral, sem retenção, e investiga (o incidente fica aberto e é da
equipe). Depois do check-in, ou com ausência do cliente registrada, quem decide é a equipe."""

from __future__ import annotations

import logging
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from trato.api.ausencia_base import do_pedido as ausencia_do_pedido
from trato.api.auth import Usuario
from trato.api.avisos import avisar_partes
from trato.api.contexto import (
    ESTADOS_CONTRATADOS,
    Contexto,
    obter_contexto,
    usuario_do_proprio_pedido,
)
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, Pedido
from trato.persistencia.ausencias import AGUARDANDO_ESPERA, PENDENTES
from trato.persistencia.incidentes import ENCERRADO, Incidente

log = logging.getLogger("trato.seguranca")
TIPO = "pessoa_diferente"
# Antes do check-in: o serviço ainda não começou.
CANCELAVEIS = (Estado.PAGO_E_RETIDO, Estado.AGENDADO)
_SISTEMA = Ator(Papel.SISTEMA, "seguranca")

router = APIRouter(prefix="/v1/pedidos", tags=["segurança"])


def cancelado_por_pessoa_diferente(contexto: Contexto, pedido_id: str) -> bool:
    return any(
        e.acao is Acao.CANCELAR_PESSOA_DIFERENTE for e in contexto.pedidos.eventos(pedido_id)
    )


def sinais_antifraude(contexto: Contexto, incidente: Incidente) -> list[str]:
    """Só para a equipe olhar: não bloqueia, não retém nem atrasa o reembolso (9.5 basta
    relatar). Calculado na leitura, dos incidentes e da ausência do pedido."""
    if incidente.tipo != TIPO or incidente.pedido_id is None:
        return []
    pedido = contexto.pedidos.obter(incidente.pedido_id)
    if pedido is None:
        return []
    sinais: list[str] = []
    achados, _ = contexto.incidentes.listar(None, None, 500, 0)
    pedidos = {i.pedido_id for i in achados if i.tipo == TIPO and i.pedido_id}
    do_cliente = 0
    for pid in pedidos:
        outro = contexto.pedidos.obter(pid)
        do_cliente += outro is not None and outro.cliente_id == pedido.cliente_id
    if do_cliente > 1:
        sinais.append(f"relato_repetido_do_cliente:{do_cliente}")
    ausencia = ausencia_do_pedido(contexto, pedido)
    if ausencia is not None and ausencia.status == AGUARDANDO_ESPERA:
        sinais.append("relato_durante_espera_de_ausencia")
    return sinais


def _avisar_equipe_dos_sinais(contexto: Contexto, pedido_id: str) -> None:
    """Aviso é secundário: nunca derruba nem desfaz o relato e o reembolso."""
    try:
        notificador = contexto.extras.get("notificador")
        achados, _ = contexto.incidentes.listar(None, pedido_id, 100, 0)
        item = next((i for i in achados if i.tipo == TIPO), None)
        if notificador is None or item is None or not sinais_antifraude(contexto, item):
            return
        for pessoa in contexto.incidentes.equipe_de_seguranca():
            notificador.notificar(
                Evento.INCIDENTE_SINAL_FRAUDE,
                pessoa,
                chave=f"incidente:{item.id}:sinal",
                corpo=f"O incidente {item.protocolo} tem sinal para conferir. Veja no painel.",
            )
    except Exception:  # noqa: BLE001
        log.exception("Aviso de sinal antifraude falhou (%s)", pedido_id)


def cancelar_com_reembolso_integral(contexto: Contexto, pedido: Pedido) -> None:
    """Dentro de uma transação, com o pedido travado e lido depois da trava. O dinheiro sai
    pelo caminho de todo cancelamento (idempotente por pedido e operação)."""
    transicao = estados.transicionar(
        pedido, Acao.CANCELAR_PESSOA_DIFERENTE, _SISTEMA, contexto.agora()
    )
    gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    contexto.cancelamentos.descartar_proposta(pedido.id)  # nenhuma retenção sobrevive
    for gancho in contexto.apos_transicao:
        gancho(pedido, gravado, Acao.CANCELAR_PESSOA_DIFERENTE, contexto)
    avisar_partes(
        contexto,
        Evento.PEDIDO_CANCELADO_SEGURANCA,
        (pedido.cliente_id, pedido.profissional_id),
        pedido_id=pedido.id,
        chave=f"{pedido.id}:pessoa_diferente",
        corpo="O pedido foi cancelado por um relato de segurança e o valor pago volta por "
        "inteiro ao cliente (Termos 9.5). O Trato vai apurar o caso.",
    )


class RelatoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    descricao: str | None = Field(None, max_length=4000, description="O que aconteceu.")


class RelatoOut(BaseModel):
    protocolo: str | None
    cancelado: bool = Field(description="true: pedido cancelado com reembolso integral.")
    estado_pedido: str
    mensagem: str


def _incidente(contexto: Contexto, pedido_id: str, descricao: str) -> Incidente:
    achados, _ = contexto.incidentes.listar(None, pedido_id, 100, 0)
    for item in achados:
        if item.tipo == TIPO and item.status != ENCERRADO:
            return item
    agora = contexto.agora()
    horas = contexto.config.carregar().incidente_seguranca_cautela_horas
    novo, _ = contexto.incidentes.abrir(
        Incidente(
            tipo=TIPO,
            descricao=descricao,
            canal="app",
            contato="Conta do cliente no aplicativo",
            pedido_id=pedido_id,
            aberto_em=agora,
            cautela_ate=agora + timedelta(hours=horas),
        )
    )
    return novo


@router.post(
    "/{pedido_id}/seguranca/pessoa-diferente",
    response_model=RelatoOut,
    summary="Cliente: chegou uma pessoa diferente da que aparece no app (9.5)",
    description="Abre o relato de segurança e, antes do check-in, cancela o pedido com "
    "reembolso integral. Repetir devolve o mesmo resultado.",
)
def relatar(
    pedido_id: str,
    corpo: RelatoIn | None = None,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
) -> RelatoOut:
    with contexto.transacao():
        travar = getattr(contexto.pedidos, "travar", None)
        if travar is not None:
            travar(pedido_id)
        pedido = contexto.pedidos.obter(pedido_id)
        if pedido is None or usuario.id not in (pedido.cliente_id, pedido.profissional_id):
            raise HTTPException(404, "Pedido não encontrado.")
        if usuario.id != pedido.cliente_id:
            raise HTTPException(403, "Só o cliente do pedido faz este relato.")
        if not contexto.incidentes.disponivel():
            raise HTTPException(
                503, "O relato pelo app está indisponível. Fale agora com o atendimento."
            )
        feito = cancelado_por_pessoa_diferente(contexto, pedido.id)
        if not feito and pedido.estado not in ESTADOS_CONTRATADOS:
            raise HTTPException(409, "Este pedido não tem serviço contratado em aberto.")
        descricao = (corpo.descricao if corpo else None) or (
            "Chegou uma pessoa diferente da que aparece no aplicativo."
        )
        if feito:
            achados, _ = contexto.incidentes.listar(None, pedido.id, 100, 0)
            protocolo = next((i.protocolo for i in achados if i.tipo == TIPO), None)
        else:
            protocolo = _incidente(contexto, pedido.id, descricao).protocolo
            ausencia = ausencia_do_pedido(contexto, pedido)
            em_analise = ausencia is not None and ausencia.status in PENDENTES
            if (
                pedido.estado in CANCELAVEIS
                and pedido.cliente_ausente_em is None
                and not em_analise
            ):
                cancelar_com_reembolso_integral(contexto, pedido)
                feito = True
        atual = contexto.pedidos.obter(pedido.id)
    _avisar_equipe_dos_sinais(contexto, pedido_id)  # depois de gravado
    return RelatoOut(
        protocolo=protocolo,
        cancelado=feito,
        estado_pedido=atual.estado.value,
        mensagem="Pedido cancelado: o valor pago volta por inteiro. O Trato vai apurar o caso."
        if feito
        else "Relato registrado e o valor fica retido. A equipe vai analisar o caso.",
    )
