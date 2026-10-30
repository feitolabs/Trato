"""LGPD: exportar dados, pedir exclusão (anonimização) e registrar consentimentos (F8.3)."""

from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI

    from trato.seguranca.estado import Seguranca


def registrar_rotas(app: FastAPI, seg: Seguranca | None = None) -> FastAPI:
    """Liga as rotas de LGPD. Chamada por `trato.seguranca.registrar_rotas` (que passa `seg`);
    sozinha, usa a segurança já instalada no app."""
    from trato.api.contexto import Contexto
    from trato.config import obter_config
    from trato.lgpd.config import obter_config_lgpd
    from trato.lgpd.memoria import FonteDadosEmMemoria, criar_repositorios_memoria
    from trato.lgpd.rotas import router
    from trato.lgpd.servico import ServicoLgpd

    seg = seg or app.state.seguranca
    app.include_router(router)
    config = obter_config_lgpd()
    memoria: dict[str, ServicoLgpd] = {}

    def fabrica(aplicativo: FastAPI) -> ServicoLgpd | None:
        """Repositórios do contexto (`extras["lgpd"]`, Postgres) ou, só em modo memória, os de
        memória. Em modo Postgres sem adaptador responde 503 em vez de perder dado em silêncio."""
        contexto: Contexto | None = getattr(aplicativo.state, "contexto", None)
        if contexto is not None and "lgpd" in contexto.extras:
            return ServicoLgpd(config, contexto.extras["lgpd"], seg)  # type: ignore[arg-type]
        if obter_config().trato_persistencia.strip().lower() != "memoria":
            return None
        if "servico" not in memoria:
            leitores = {}
            if contexto is not None:
                leitores = {
                    "pedidos_como_cliente": lambda u: [
                        vars(p) for p in contexto.pedidos.listar_do_usuario(u, True)
                    ],
                    "pedidos_como_profissional": lambda u: [
                        vars(p) for p in contexto.pedidos.listar_do_usuario(u, False)
                    ],
                }
            repos = criar_repositorios_memoria(FonteDadosEmMemoria(leitores=leitores))
            memoria["servico"] = ServicoLgpd(config, repos, seg)
        return memoria["servico"]

    app.state.lgpd_fabrica = fabrica
    return app
