"""Liga a segurança a um app FastAPI. Chamada por `trato.seguranca.registrar_rotas(app)`."""

from __future__ import annotations

from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from trato.seguranca.config import ConfigSeguranca, obter_config_seguranca
from trato.seguranca.contadores import Contadores
from trato.seguranca.conversas import ConversasVigiadas
from trato.seguranca.duplicidade import IdentificadoresEmMemoria
from trato.seguranca.estado import Seguranca
from trato.seguranca.http import MiddlewareProtecao
from trato.seguranca.logs import instalar_filtro_logs


def instalar_seguranca(
    app: FastAPI,
    config: ConfigSeguranca | None = None,
    *,
    contadores: Contadores | None = None,
) -> FastAPI:
    from trato.lgpd import registrar_rotas as registrar_lgpd
    from trato.seguranca.rotas import router

    config = config or obter_config_seguranca()
    instalar_filtro_logs()

    def destino_auditoria():  # type: ignore[no-untyped-def]
        contexto = getattr(app.state, "contexto", None)
        return contexto.extras.get("auditoria") if contexto is not None else None

    seg = Seguranca(config, contadores=contadores, destino_auditoria=destino_auditoria)
    seg.identificadores = IdentificadoresEmMemoria()
    app.state.seguranca = seg

    def vigiar_conversas() -> None:
        """O contexto pode ser ligado depois do app: embrulha as conversas na primeira chamada."""
        contexto = getattr(app.state, "contexto", None)
        if contexto is not None and not isinstance(contexto.conversas, ConversasVigiadas):
            contexto.conversas = ConversasVigiadas(contexto.conversas, seg)

    vigiar_conversas()
    app.include_router(router)
    registrar_lgpd(app, seg)
    # O último adicionado fica por fora: CORS responde o preflight antes de tudo.
    app.add_middleware(MiddlewareProtecao, seg=seg, ao_primeiro_uso=vigiar_conversas)
    if config.cors_origens:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.cors_origens,
            allow_methods=config.cors_metodos,
            allow_headers=config.cors_cabecalhos,
            allow_credentials=False,
            max_age=600,
        )
    return app
