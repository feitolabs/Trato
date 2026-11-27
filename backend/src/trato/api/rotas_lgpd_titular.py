"""Rotas do titular para pedidos LGPD e revisão de decisão automatizada (14.9 e 14.10)."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_atual
from trato.persistencia.lgpd_titular import (
    PRAZO_PADRAO_DIAS,
    PedidoTitularLgpd,
    calcular_responder_ate,
)

router = APIRouter(prefix="/v1/me/lgpd", tags=["lgpd"])

TipoPedidoTitular = Literal[
    "confirmacao",
    "acesso",
    "correcao",
    "anonimizacao_bloqueio_eliminacao",
    "portabilidade",
    "eliminacao_consentimento",
    "compartilhamento",
    "nao_consentir",
    "revogacao_consentimento",
    "revisao_decisao_automatizada",
]
DecisaoAutomatizada = Literal[
    "ocultacao_contato",
    "documentos_rosto",
    "alerta_fraude",
    "ordem_resultados",
    "outra",
]


class AbrirPedidoTitularIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    tipo: TipoPedidoTitular
    descricao: str = Field(default="", max_length=4000)
    decisao_automatizada: DecisaoAutomatizada | None = None
    referencia_tipo: str | None = Field(default=None, min_length=1, max_length=60)
    referencia_id: str | None = Field(default=None, min_length=1, max_length=64)
    exclusao_id: str | None = Field(default=None, min_length=1, max_length=64)


class PedidoTitularUsuarioOut(BaseModel):
    id: str
    protocolo: str
    tipo: TipoPedidoTitular
    decisao_automatizada: DecisaoAutomatizada | None = None
    referencia_tipo: str | None = None
    referencia_id: str | None = None
    descricao: str
    canal: str
    exclusao_id: str | None = None
    status: str
    aberto_em: datetime
    responder_ate: datetime
    resposta: str | None = None
    motivo_nao_atendido: str | None = None
    criterios_informados: str | None = None
    respondido_em: datetime | None = None


class PaginaPedidosTitularUsuarioOut(BaseModel):
    itens: list[PedidoTitularUsuarioOut]
    total: int
    limite: int
    deslocamento: int


def _out(p: PedidoTitularLgpd) -> PedidoTitularUsuarioOut:
    return PedidoTitularUsuarioOut(
        id=p.id,
        protocolo=p.protocolo,
        tipo=p.tipo,  # type: ignore[arg-type]
        decisao_automatizada=p.decisao_automatizada,  # type: ignore[arg-type]
        referencia_tipo=p.referencia_tipo,
        referencia_id=p.referencia_id,
        descricao=p.descricao,
        canal=p.canal,
        exclusao_id=p.exclusao_id,
        status=p.status,
        aberto_em=p.aberto_em,
        responder_ate=p.responder_ate,
        resposta=p.resposta,
        motivo_nao_atendido=p.motivo_nao_atendido,
        criterios_informados=p.criterios_informados,
        respondido_em=p.respondido_em,
    )


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.lgpd_titular.disponivel():
        raise HTTPException(
            503,
            "Pedidos de titular LGPD indisponíveis: a tabela ainda não existe no banco de dados.",
        )


def _prazo_dias(contexto: Contexto) -> int:
    valor = contexto.config.parametro_inteiro("lgpd_pedido_resposta_dias")
    if valor is not None and 1 <= valor <= 15:
        return valor
    return PRAZO_PADRAO_DIAS


@router.post(
    "/pedidos",
    response_model=PedidoTitularUsuarioOut,
    status_code=201,
    summary="Abrir pedido de titular LGPD ou revisão de decisão automatizada (14.9 e 14.10)",
)
def abrir_pedido_titular(
    corpo: AbrirPedidoTitularIn,
    resposta: Response,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoTitularUsuarioOut:
    _exigir_tabela(contexto)
    eh_auto = corpo.tipo == "revisao_decisao_automatizada"
    if eh_auto and corpo.decisao_automatizada is None:
        raise HTTPException(
            422, "Informe `decisao_automatizada` ao pedir revisão de decisão automatizada."
        )
    if not eh_auto and corpo.decisao_automatizada is not None:
        raise HTTPException(
            422, "`decisao_automatizada` só pode ser informada em `revisao_decisao_automatizada`."
        )
    if (corpo.referencia_tipo is None) != (corpo.referencia_id is None):
        raise HTTPException(422, "`referencia_tipo` e `referencia_id` devem ser informados juntos.")

    agora = contexto.agora()
    responder_ate = calcular_responder_ate(agora, _prazo_dias(contexto))
    pedido, eh_novo = contexto.lgpd_titular.abrir(
        usuario_id=usuario.id,
        tipo=corpo.tipo,
        decisao_automatizada=corpo.decisao_automatizada,
        referencia_tipo=corpo.referencia_tipo,
        referencia_id=corpo.referencia_id,
        descricao=corpo.descricao,
        canal="app",
        exclusao_id=corpo.exclusao_id,
        aberto_em=agora,
        responder_ate=responder_ate,
    )
    if not eh_novo:
        resposta.status_code = 200
    return _out(pedido)


@router.get(
    "/pedidos",
    response_model=PaginaPedidosTitularUsuarioOut,
    summary="Listar meus pedidos de titular LGPD",
)
def listar_meus_pedidos_titular(
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> PaginaPedidosTitularUsuarioOut:
    _exigir_tabela(contexto)
    itens, total = contexto.lgpd_titular.listar_do_usuario(usuario.id, limite, deslocamento)
    return PaginaPedidosTitularUsuarioOut(
        itens=[_out(p) for p in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )
