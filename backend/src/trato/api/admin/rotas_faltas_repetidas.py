"""Indicador/fila de faltas e cancelamentos repetidos do profissional (Termos 7.7)."""

from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel

from trato.api.admin.contexto import Operador, exigir
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/profissionais", tags=["admin: profissionais"])


class FaltaRepetidaOut(BaseModel):
    profissional_id: str
    total_cancelamentos: int
    ultimo_cancelamento_em: datetime
    periodo_dias: int


@router.get(
    "/faltas-repetidas",
    response_model=list[FaltaRepetidaOut],
    summary="Profissionais com cancelamentos/faltas repetidas no período (Termos 7.7)",
)
def listar_faltas_repetidas(
    dias: int = Query(90, ge=1, le=365),
    minimo: int = Query(2, ge=1, le=100),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[FaltaRepetidaOut]:
    desde = contexto.agora() - timedelta(days=dias)
    itens = contexto.cancelamentos.faltas_repetidas(desde, minimo)
    return [
        FaltaRepetidaOut(
            profissional_id=x.profissional_id,
            total_cancelamentos=x.total_cancelamentos,
            ultimo_cancelamento_em=x.ultimo_cancelamento_em,
            periodo_dias=dias,
        )
        for x in itens
    ]
