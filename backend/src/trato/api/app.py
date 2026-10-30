"""Montagem da API: rotas, tratadores de erro e contexto."""

from __future__ import annotations

from fastapi import APIRouter, FastAPI

from trato import __version__
from trato.api import (
    rotas_app,
    rotas_financeiro,
    rotas_pedidos,
    rotas_profissional_cadastro,
    rotas_upload,
    rotas_webhook,
)
from trato.api.admin import criar_router_admin
from trato.api.contexto import Contexto
from trato.api.erros import instalar_tratadores
from trato.config import obter_config
from trato.seguranca.config import parametros_docs


def criar_router() -> APIRouter:
    roteador = APIRouter()
    roteador.include_router(rotas_pedidos.router)
    roteador.include_router(rotas_app.router)
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
    rotas_upload.registrar_rotas(app)
    rotas_profissional_cadastro.registrar_rotas(app)
    instalar_tratadores(app)
    if contexto is not None:
        app.state.contexto = contexto
    return app


def criar_app(contexto: Contexto | None = None) -> FastAPI:
    docs = parametros_docs(obter_config().trato_ambiente)
    return instalar(FastAPI(title="Trato API", version=__version__, **docs), contexto)
