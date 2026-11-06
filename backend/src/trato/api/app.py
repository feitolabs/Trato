"""Montagem da API: rotas, tratadores de erro e contexto."""

from __future__ import annotations

from fastapi import APIRouter, FastAPI
from starlette.middleware.cors import CORSMiddleware

from trato import __version__
from trato.api import (
    conta,
    rotas_app,
    rotas_cadastro,
    rotas_financeiro,
    rotas_legal,
    rotas_pedido_contrato,
    rotas_pedidos,
    rotas_profissional_cadastro,
    rotas_upload,
    rotas_webhook,
)
from trato.api.admin import criar_router_admin
from trato.api.contexto import Contexto
from trato.api.erros import instalar_tratadores
from trato.config import obter_config
from trato.seguranca.config import obter_config_seguranca, parametros_docs


def criar_router() -> APIRouter:
    roteador = APIRouter()
    roteador.include_router(rotas_legal.router)
    roteador.include_router(rotas_cadastro.router)
    roteador.include_router(rotas_pedidos.router)
    roteador.include_router(rotas_app.router)
    roteador.include_router(rotas_pedido_contrato.router)
    roteador.include_router(conta.router)
    roteador.include_router(rotas_financeiro.router)
    roteador.include_router(rotas_webhook.router)
    roteador.include_router(criar_router_admin())
    return roteador


def instalar(app: FastAPI, contexto: Contexto | None = None) -> FastAPI:
    """Liga as rotas v1 ao app. Sem `contexto`, as rotas respondem 503 até alguém ligá-lo
    (`app.state.contexto = ...`), o que acontece quando os adaptadores reais existirem."""
    from trato.notificacoes import registrar_rotas  # antes: o GET /v1/notificacoes daqui vale

    registrar_rotas(app, contexto)
    app.include_router(criar_router())
    banco = contexto.extras.get("banco") if contexto is not None else None
    if banco is not None:  # com Postgres, o perfil, catálogo e uploads moram no banco
        from trato.persistencia.profissionais import CatalogoPostgres, ProfissionaisPostgres
        from trato.persistencia.uploads import UploadsPostgres

        rotas_upload.registrar_rotas(app, repo=UploadsPostgres(banco))
        rotas_profissional_cadastro.registrar_rotas(
            app, ProfissionaisPostgres(banco), CatalogoPostgres(banco)
        )
    else:
        rotas_upload.registrar_rotas(app)
        rotas_profissional_cadastro.registrar_rotas(app)
    instalar_tratadores(app)
    cfg_seg = obter_config_seguranca()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cfg_seg.cors_origens or [],
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_credentials=True,
        allow_methods=cfg_seg.cors_metodos or ["*"],
        allow_headers=cfg_seg.cors_cabecalhos or ["*"],
    )
    if contexto is not None:
        app.state.contexto = contexto
    return app


def criar_app(contexto: Contexto | None = None) -> FastAPI:
    docs = parametros_docs(obter_config().trato_ambiente)
    return instalar(FastAPI(title="Trato API", version=__version__, **docs), contexto)
