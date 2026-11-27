"""Montagem da API: rotas, tratadores de erro e contexto."""

from __future__ import annotations

from fastapi import APIRouter, FastAPI
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware

from trato import __version__
from trato.api import (
    ausencia,
    compensacoes,
    conta,
    desistencia,
    pessoa_diferente,
    rotas_a_caminho,
    rotas_app,
    rotas_avaliacoes_moderacao,
    rotas_cadastro,
    rotas_cep,
    rotas_config_publica,
    rotas_contestacao_disputa,
    rotas_contratacao,
    rotas_denuncia,
    rotas_exclusividade,
    rotas_exclusividade_cliente,
    rotas_financeiro,
    rotas_indicacao,
    rotas_legal,
    rotas_lgpd_titular,
    rotas_materiais_contestacao,
    rotas_medidas,
    rotas_mei,
    rotas_pedido_contrato,
    rotas_pedidos,
    rotas_profissional_cadastro,
    rotas_reagendamento,
    rotas_recorrencia,
    rotas_retorno_conta,
    rotas_sac,
    rotas_upload,
    rotas_webhook,
)
from trato.api.admin import criar_router_admin
from trato.api.contexto import ContaBloqueada, Contexto, tratar_conta_bloqueada
from trato.api.erros import instalar_tratadores
from trato.api.maioridade import ErroMaioridade, tratar_maioridade
from trato.api.medicao import MedidorConsultas, medicao_ligada
from trato.api.validade import OrcamentoVencido, tratar_orcamento_vencido
from trato.config import obter_config
from trato.persistencia.captura_auditoria import CabecalhoAuditoria
from trato.seguranca.config import obter_config_seguranca, parametros_docs


def criar_router() -> APIRouter:
    roteador = APIRouter()
    roteador.include_router(rotas_legal.router)
    roteador.include_router(rotas_lgpd_titular.router)
    roteador.include_router(rotas_cadastro.router)
    roteador.include_router(rotas_cep.router)
    roteador.include_router(rotas_mei.router)
    roteador.include_router(rotas_pedidos.router)
    roteador.include_router(rotas_config_publica.router)
    roteador.include_router(rotas_config_publica.router_catalogo)
    roteador.include_router(rotas_app.router)
    roteador.include_router(rotas_avaliacoes_moderacao.router)
    roteador.include_router(rotas_pedido_contrato.router)
    roteador.include_router(rotas_exclusividade.router)
    roteador.include_router(rotas_a_caminho.router)
    roteador.include_router(rotas_reagendamento.router)
    roteador.include_router(rotas_denuncia.router)
    roteador.include_router(rotas_indicacao.router)
    roteador.include_router(rotas_recorrencia.router)
    roteador.include_router(rotas_retorno_conta.router)
    roteador.include_router(conta.router)
    roteador.include_router(rotas_financeiro.router)
    roteador.include_router(rotas_contratacao.router)
    roteador.include_router(rotas_webhook.router)
    roteador.include_router(desistencia.router)
    roteador.include_router(ausencia.router)
    roteador.include_router(rotas_sac.router)
    roteador.include_router(rotas_materiais_contestacao.router)
    roteador.include_router(rotas_medidas.router)
    roteador.include_router(compensacoes.router)
    roteador.include_router(rotas_contestacao_disputa.router)
    roteador.include_router(pessoa_diferente.router)
    roteador.include_router(rotas_exclusividade_cliente.router)
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
    app.add_exception_handler(ErroMaioridade, tratar_maioridade)
    app.add_exception_handler(ContaBloqueada, tratar_conta_bloqueada)
    app.add_exception_handler(OrcamentoVencido, tratar_orcamento_vencido)
    cfg_seg = obter_config_seguranca()

    app.add_middleware(CabecalhoAuditoria)
    # Respostas JSON acima de 1 KB vão compactadas (listas no 4G).
    app.add_middleware(GZipMiddleware, minimum_size=1000)
    if medicao_ligada():
        app.add_middleware(MedidorConsultas)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cfg_seg.cors_origens or [],
        allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        allow_credentials=True,
        expose_headers=["X-Auditoria-Id"],
        allow_methods=cfg_seg.cors_metodos or ["*"],
        allow_headers=cfg_seg.cors_cabecalhos or ["*"],
    )
    if contexto is not None:
        app.state.contexto = contexto
    return app


def criar_app(contexto: Contexto | None = None) -> FastAPI:
    docs = parametros_docs(obter_config().trato_ambiente)
    return instalar(FastAPI(title="Trato API", version=__version__, **docs), contexto)
