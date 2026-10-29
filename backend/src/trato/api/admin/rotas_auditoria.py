"""Auditoria: listar com filtros e verificar a cadeia de hash."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Query

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import CadeiaOut, EntradaAuditoriaOut, Pagina
from trato.api.admin.papeis import Permissao
from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/auditoria", tags=["admin: auditoria"])


@router.get("", response_model=Pagina[EntradaAuditoriaOut], summary="Listar a trilha")
def listar(
    acao: str | None = Query(None, max_length=100, description="Prefixo: `config.` etc."),
    ator_id: str | None = None,
    entidade: str | None = None,
    entidade_id: str | None = None,
    desde: datetime | None = None,
    ate: datetime | None = None,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.AUDITORIA_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[EntradaAuditoriaOut]:
    filtro = FiltroAuditoria(acao, ator_id, entidade, entidade_id, desde, ate)
    itens, total = admin.auditoria.listar(filtro, limite, deslocamento)
    return Pagina(
        itens=[EntradaAuditoriaOut.model_validate(i) for i in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/verificar-cadeia",
    response_model=CadeiaOut,
    summary="Verificar a cadeia de hash",
    description="POST porque a conferência percorre a tabela inteira e fica registrada.",
)
def verificar_cadeia(
    operador: Operador = Depends(exigir(Permissao.AUDITORIA_VERIFICAR_CADEIA)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CadeiaOut:
    falha = admin.auditoria.verificar_cadeia()
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="auditoria.cadeia_verificada",
        depois={"integra": falha is None, "primeira_falha_id": falha},
        motivo="Conferência da cadeia de hash da auditoria.",
    )
    return CadeiaOut(integra=falha is None, primeira_falha_id=falha, verificada_em=contexto.agora())
