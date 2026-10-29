"""Fábrica do app: escolhe repositórios em memória ou Postgres por configuração.

  TRATO_PERSISTENCIA=memoria   (padrão) rotas sem repositórios (503) até alguém ligar o contexto;
                               os testes montam o contexto com `api.memoria`.
  TRATO_PERSISTENCIA=postgres  Postgres do Supabase via DATABASE_URL + auth com o JWT do Supabase.

Em modo postgres, ledger, disputas, garantias, avaliações e eventos de webhook continuam EM
MEMÓRIA: as tabelas deles (F3.5/F3.6) ainda não existem no banco e a F3.5 está sendo refeita
(caminho A).
Reiniciar o servidor perde esses dados. Não usar assim em produção.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI

from trato import __version__
from trato.api.app import instalar
from trato.api.auth import ProvedorAuth
from trato.api.contexto import Contexto, agora_utc
from trato.api.memoria import (
    DisputasEmMemoria,
    EventosWebhookEmMemoria,
    GarantiasEmMemoria,
    LedgerEmMemoria,
)
from trato.config import Config, obter_config
from trato.persistencia.app_extras import TaxaPostgres, VerificacoesPostgres
from trato.persistencia.auditoria import AuditoriaPostgres
from trato.persistencia.conexao import Banco
from trato.persistencia.config import ConfigPostgres
from trato.persistencia.contratos import ContratosPostgres
from trato.persistencia.conversas import ConversasPostgres, NotificacoesPostgres
from trato.persistencia.execucao import ExecucaoPostgres
from trato.persistencia.orcamentos import OrcamentosPostgres
from trato.persistencia.pedidos import PedidosPostgres
from trato.persistencia.usuarios import UsuariosPostgres

PERSISTENCIAS = ("memoria", "postgres")


def criar_contexto_postgres(
    banco: Banco,
    config: Config | None = None,
    *,
    agora: Callable[[], datetime] = agora_utc,
    auth: ProvedorAuth | None = None,
) -> Contexto:
    """Monta o contexto com repositórios Postgres. `auth` só é trocado em testes."""
    config = config or obter_config()
    segredo_codigos = config.trato_codigo_segredo.get_secret_value()
    if not segredo_codigos:
        raise RuntimeError("Defina TRATO_CODIGO_SEGREDO no .env (segredo dos códigos de check-in).")
    usuarios = UsuariosPostgres(banco)
    if auth is None:
        from trato.api.auth_supabase import ProvedorAuthSupabase

        if not (config.supabase_jwt_secret.get_secret_value() or config.supabase_jwks_url):
            raise RuntimeError("Defina SUPABASE_JWT_SECRET ou SUPABASE_JWKS_URL no .env.")
        auth = ProvedorAuthSupabase(
            usuarios,
            segredo_hs256=config.supabase_jwt_secret.get_secret_value,
            jwks_url=config.supabase_jwks_url,
        )
    conversas = ConversasPostgres(banco)
    notificacoes = NotificacoesPostgres(banco)
    return Contexto(
        auth=auth,
        pedidos=PedidosPostgres(banco, lambda: segredo_codigos),
        orcamentos=OrcamentosPostgres(banco),
        contratos=ContratosPostgres(banco),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigPostgres(banco),
        agora=agora,
        conversas=conversas,
        notificacoes=notificacoes,
        usuarios=usuarios,
        verificacoes=VerificacoesPostgres(banco),
        taxa=TaxaPostgres(banco),
        extras={
            "usuarios": usuarios,
            "execucao": ExecucaoPostgres(banco),
            "conversas": conversas,
            "notificacoes": notificacoes,
            "auditoria": AuditoriaPostgres(banco),
            "banco": banco,
        },
    )


def criar_app_da_config(config: Config | None = None) -> FastAPI:
    """O app de produção/desenvolvimento, conforme `TRATO_PERSISTENCIA`."""
    config = config or obter_config()
    modo = config.trato_persistencia.strip().lower()
    if modo not in PERSISTENCIAS:
        raise RuntimeError(f"TRATO_PERSISTENCIA inválido: {modo!r} (use memoria ou postgres).")
    if modo == "memoria":
        return instalar(FastAPI(title="Trato API", version=__version__))

    dsn = config.database_url.get_secret_value()
    if not dsn:
        raise RuntimeError("Defina DATABASE_URL no .env para usar TRATO_PERSISTENCIA=postgres.")
    banco = Banco(dsn, papel=config.trato_banco_papel, abrir=False)

    @asynccontextmanager
    async def ciclo(_: FastAPI) -> AsyncIterator[None]:
        banco.abrir()
        try:
            yield
        finally:
            banco.fechar()

    app = FastAPI(title="Trato API", version=__version__, lifespan=ciclo)
    return instalar(app, criar_contexto_postgres(banco, config))
