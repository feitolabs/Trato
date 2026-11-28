"""Rotas admin para análise e decisão de eventos externos / força maior (Termos 7.8 e 22.6)."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api import forca_maior as regras
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.api.forca_maior import EventoForcaMaiorOut

router = APIRouter(prefix="/v1/admin/forca-maior", tags=["admin: força maior"])


class DecidirForcaMaiorIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    decisao: Literal["aprovado", "recusado"]
    justificativa: str = Field(min_length=10, max_length=500)
    chave_idempotencia: str = Field(min_length=8, max_length=120)


@router.get(
    "",
    response_model=Pagina[EventoForcaMaiorOut],
    summary="Fila de eventos externos / força maior",
)
def listar_forca_maior_admin(
    status: Literal["pendente", "aprovado", "recusado"] | None = Query(None),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[EventoForcaMaiorOut]:
    regras.exigir_tabela(contexto)
    itens, total = contexto.forca_maior.listar(status, limite, deslocamento)
    return Pagina(
        itens=[regras.saida(x) for x in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{evento_id}/decisao",
    response_model=EventoForcaMaiorOut,
    summary="Aprovar ou recusar solicitação de força maior",
)
def decidir_forca_maior(
    evento_id: str,
    corpo: DecidirForcaMaiorIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> EventoForcaMaiorOut:
    regras.exigir_tabela(contexto)
    servico = getattr(request.app.state, "servico_pagamento", None)
    gravado, idempotente = regras.efetivar_decisao(
        contexto,
        admin,
        servico,
        operador,
        evento_id,
        corpo.decisao,
        corpo.justificativa,
        corpo.chave_idempotencia,
    )
    return regras.saida(gravado, idempotente=idempotente)
