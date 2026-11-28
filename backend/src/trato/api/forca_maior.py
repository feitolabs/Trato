"""Regras de evento externo / força maior (Termos 7.8 e 22.6)."""

from __future__ import annotations

import threading
from contextlib import nullcontext
from datetime import datetime
from typing import Any, Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field

from trato.api.admin.papeis import PapelEquipe
from trato.financeiro.ledger import reembolso_total_com_custo
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, TransicaoInvalida
from trato.persistencia.forca_maior import EventoForcaMaior

_TRAVA_EM_MEMORIA = threading.RLock()


class EventoForcaMaiorOut(BaseModel):
    id: str
    pedido_id: str
    solicitante_id: str
    solicitante_papel: Literal["cliente", "profissional"]
    acao_solicitada: Literal["reagendar", "cancelar"]
    descricao: str
    comprovantes: list[str]
    status: Literal["pendente", "aprovado", "recusado"]
    criado_em: datetime | None
    analista_id: str | None
    justificativa_decisao: str | None
    decidido_em: datetime | None
    chave_idempotencia: str | None
    idempotente: bool = Field(
        False, description="True quando a mesma chave repetiu uma decisão já gravada."
    )


class EventoForcaMaiorAppOut(BaseModel):
    id: str
    pedido_id: str
    solicitante_id: str
    solicitante_papel: Literal["cliente", "profissional"]
    acao_solicitada: Literal["reagendar", "cancelar"]
    descricao: str
    comprovantes: list[str]
    status: Literal["pendente", "aprovado", "recusado"]
    criado_em: datetime | None
    justificativa_decisao: str | None
    decidido_em: datetime | None


def exigir_tabela(contexto: Any) -> None:
    if not contexto.forca_maior.disponivel():
        raise HTTPException(
            503, "Os registros de força maior ainda não estão disponíveis no banco."
        )


def saida(item: EventoForcaMaior, *, idempotente: bool = False) -> EventoForcaMaiorOut:
    return EventoForcaMaiorOut(
        id=item.id,
        pedido_id=item.pedido_id,
        solicitante_id=item.solicitante_id,
        solicitante_papel=item.solicitante_papel,  # type: ignore[arg-type]
        acao_solicitada=item.acao_solicitada,  # type: ignore[arg-type]
        descricao=item.descricao,
        comprovantes=list(item.comprovantes),
        status=item.status,  # type: ignore[arg-type]
        criado_em=item.criado_em,
        analista_id=item.analista_id,
        justificativa_decisao=item.justificativa_decisao,
        decidido_em=item.decidido_em,
        chave_idempotencia=item.chave_idempotencia,
        idempotente=idempotente,
    )


def saida_app(item: EventoForcaMaior) -> EventoForcaMaiorAppOut:
    return EventoForcaMaiorAppOut(
        id=item.id,
        pedido_id=item.pedido_id,
        solicitante_id=item.solicitante_id,
        solicitante_papel=item.solicitante_papel,  # type: ignore[arg-type]
        acao_solicitada=item.acao_solicitada,  # type: ignore[arg-type]
        descricao=item.descricao,
        comprovantes=list(item.comprovantes),
        status=item.status,  # type: ignore[arg-type]
        criado_em=item.criado_em,
        justificativa_decisao=item.justificativa_decisao,
        decidido_em=item.decidido_em,
    )


def _alcada_do_operador(operador: Any) -> int:
    alcada = operador.membro.alcada_centavos
    if operador.membro.papel == PapelEquipe.ADMINISTRADOR:
        return alcada or 100_000_000_00
    return alcada or 0


def efetivar_decisao(
    contexto: Any,
    admin: Any,
    servico: Any,
    operador: Any,
    evento_id: str,
    decisao: str,
    justificativa: str,
    chave_idempotencia: str,
) -> tuple[EventoForcaMaior, bool]:
    repo = contexto.forca_maior
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext():
        with contexto.transacao():
            existente = repo.obter_por_chave(chave_idempotencia)
            if existente is not None:
                if existente.id == evento_id and existente.status == decisao:
                    return existente, True
                raise HTTPException(409, "Chave de idempotência já utilizada em outra decisão.")

            evento = repo.obter(evento_id)
            if evento is None:
                raise HTTPException(404, "Evento de força maior não encontrado.")
            if travar is not None:
                travar(evento.pedido_id)
            evento = repo.obter(evento_id)
            if evento is None:
                raise HTTPException(404, "Evento de força maior não encontrado.")
            if evento.status != "pendente":
                if evento.chave_idempotencia == chave_idempotencia and evento.status == decisao:
                    return evento, True
                raise HTTPException(409, "Este evento de força maior já foi decidido.")

            pedido = contexto.pedidos.obter(evento.pedido_id)
            if pedido is None:
                raise HTTPException(404, "Pedido do evento não encontrado.")

            agora = contexto.agora()
            valor_estornado = 0
            alcada = _alcada_do_operador(operador)
            estado_antes = pedido.estado.value

            if decisao == "aprovado" and evento.acao_solicitada == "reagendar":
                if pedido.estado in (Estado.CANCELADO, Estado.CONCLUIDO):
                    raise HTTPException(
                        409, "O pedido já está encerrado e não pode ser reagendado."
                    )

            if decisao == "aprovado" and evento.acao_solicitada == "cancelar":
                if pedido.estado in (Estado.CANCELADO, Estado.CONCLUIDO):
                    raise HTTPException(409, "O pedido já está encerrado.")
                saldos = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
                valor_em_jogo = saldos.retido + saldos.a_liberar
                total = reembolso_total_com_custo(
                    contexto.ledger.lancamentos(pedido.id),
                    pedido.id,
                    pedido.profissional_id,
                )
                devolver = total if total is not None else valor_em_jogo
                valor_alcada = max(valor_em_jogo, devolver)
                if valor_alcada > 0:
                    if servico is None:
                        raise HTTPException(
                            503,
                            "O serviço de pagamento não está ligado: não é possível estornar.",
                        )
                    if valor_alcada > alcada:
                        raise HTTPException(
                            403,
                            f"Valor do estorno ({valor_alcada} centavos) acima da sua alçada "
                            f"({alcada} centavos).",
                        )
                try:
                    transicao = estados.transicionar(
                        pedido,
                        Acao.CANCELAR_FORCA_MAIOR,
                        Ator(Papel.SISTEMA, operador.id),
                        agora,
                    )
                except TransicaoInvalida as erro:
                    raise HTTPException(409, str(erro)) from erro
                if devolver > 0:
                    valor_estornado = devolver
                    servico.aplicar_dinheiro(
                        contexto,
                        pedido,
                        operacao=f"forca_maior/{evento.id}",
                        devolver_ao_cliente=devolver,
                        repartir=False,
                        gatilho="decisao_disputa",
                        incluir_custo=total is not None,
                    )
                contexto.pedidos.salvar(transicao.pedido, transicao.evento)

            gravado = repo.decidir(
                evento.id, decisao, operador.id, justificativa, agora, chave_idempotencia
            )
            if gravado is None:
                raise HTTPException(409, "Este evento de força maior já foi decidido.")

            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="forca_maior.decidido",
                entidade="pedidos",
                entidade_id=pedido.id,
                antes={"status": "pendente", "estado_pedido": estado_antes},
                depois={
                    "evento_id": gravado.id,
                    "acao_solicitada": gravado.acao_solicitada,
                    "decisao": decisao,
                    "valor_estornado_centavos": valor_estornado,
                    "alcada_centavos": alcada,
                    "chave_idempotencia": chave_idempotencia,
                },
                motivo=justificativa,
            )
    return gravado, False
