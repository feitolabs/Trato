"""API administrativa (painel da equipe). Contrato em `docs/api-admin.md`.

Tudo aqui é novo e isolado: a única ligação com o resto da API é `instalar_admin`, chamada por
`trato.api.app`. Autorização por PAPEL da equipe (tabela `equipe`), ação sensível com motivo e
auditoria, nenhuma regra de dinheiro nova (usa `disputas/`, `pedidos/` e o ledger).
"""

from __future__ import annotations

from fastapi import APIRouter, FastAPI

from trato.api.admin import (
    rotas_auditoria,
    rotas_ausencias,
    rotas_avaliacoes,
    rotas_avisos_previos,
    rotas_catalogo,
    rotas_checkout_sem_codigo,
    rotas_compensacoes,
    rotas_config,
    rotas_contestacoes_disputa,
    rotas_conversas,
    rotas_cupons,
    rotas_dashboard,
    rotas_disputa_info,
    rotas_disputas,
    rotas_equipe,
    rotas_exclusividade,
    rotas_faltas_repetidas,
    rotas_financeiro,
    rotas_forca_maior,
    rotas_incidentes,
    rotas_indisponibilidades,
    rotas_lgpd_titular,
    rotas_materiais_contestacao,
    rotas_medidas,
    rotas_moedas,
    rotas_notificacoes,
    rotas_pagamentos,
    rotas_pedido_guardas,
    rotas_ranking,
    rotas_relatorios,
    rotas_retorno_conta,
    rotas_risco,
    rotas_sac,
    rotas_selos,
    rotas_usuarios,
    rotas_verificacoes,
)
from trato.api.admin.contexto import AdminContexto


def criar_router_admin() -> APIRouter:
    roteador = APIRouter()
    for modulo in (
        rotas_dashboard,
        rotas_verificacoes,
        rotas_disputas,
        rotas_ausencias,
        rotas_avaliacoes,
        rotas_checkout_sem_codigo,
        rotas_disputa_info,
        rotas_compensacoes,
        rotas_contestacoes_disputa,
        rotas_materiais_contestacao,
        rotas_medidas,
        rotas_avisos_previos,
        rotas_incidentes,
        rotas_indisponibilidades,
        rotas_pedido_guardas,
        rotas_lgpd_titular,
        rotas_sac,
        rotas_selos,
        rotas_conversas,
        rotas_exclusividade,
        rotas_pagamentos,
        rotas_usuarios,
        rotas_config,
        rotas_auditoria,
        rotas_catalogo,
        rotas_risco,
        rotas_notificacoes,
        rotas_cupons,
        rotas_moedas,
        rotas_ranking,
        rotas_equipe,
        rotas_relatorios,
        rotas_retorno_conta,
        rotas_faltas_repetidas,
        rotas_financeiro,
        rotas_forca_maior,
    ):
        roteador.include_router(modulo.router)
    roteador.include_router(rotas_pagamentos.router_divergencias)
    return roteador


def instalar_admin(app: FastAPI, admin: AdminContexto) -> FastAPI:
    """Liga os repositórios administrativos ao app. As ROTAS já entram por `trato.api.app`.

    Sem isto, o contexto Postgres é montado sozinho a partir de `contexto.extras['banco']`;
    sem banco, as rotas respondem 503."""
    app.state.admin = admin
    return app


__all__ = ["AdminContexto", "criar_router_admin", "instalar_admin"]
