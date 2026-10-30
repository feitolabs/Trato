"""Fábrica do app: escolhe repositórios em memória ou Postgres por configuração.

  TRATO_PERSISTENCIA=memoria   (padrão) rotas sem repositórios (503) até alguém ligar o contexto;
                               os testes montam o contexto com `api.memoria`.
  TRATO_PERSISTENCIA=postgres  Postgres do Supabase via DATABASE_URL + auth com o JWT do Supabase.

Em modo postgres TODO o dinheiro mora no banco (C1): ledger, lançamentos e partidas, disputas,
garantias e retrabalhos, avaliações, eventos de webhook e repasses (tabelas da F3.5/F3.6). Cada
operação financeira roda numa transação única (`Contexto.transacao`). Em produção a fábrica
RECUSA subir se algum repositório de dinheiro for em memória (`exigir_dinheiro_no_banco`).
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
    RepassesEmMemoria,
)
from trato.api.memoria_app import AvaliacoesEmMemoria
from trato.config import Config, obter_config
from trato.persistencia.app_extras import TaxaPostgres, VerificacoesPostgres
from trato.persistencia.auditoria import AuditoriaPostgres
from trato.persistencia.conexao import Banco
from trato.persistencia.config import ConfigPostgres
from trato.persistencia.contratos import ContratosPostgres
from trato.persistencia.conversas import ConversasPostgres, NotificacoesPostgres
from trato.persistencia.dinheiro import (
    AvaliacoesPostgres,
    DisputasPostgres,
    EventosWebhookPostgres,
    GarantiasPostgres,
    RepassesPostgres,
)
from trato.persistencia.execucao import ExecucaoPostgres
from trato.persistencia.ledger import LedgerPostgres
from trato.persistencia.orcamentos import OrcamentosPostgres
from trato.persistencia.pedido_extras import NotasMaterialPostgres, RecusasPostgres
from trato.persistencia.pedidos import PedidosPostgres
from trato.persistencia.usuarios import UsuariosPostgres
from trato.seguranca.config import parametros_docs

PERSISTENCIAS = ("memoria", "postgres")

# Repositórios que guardam dinheiro (ou prova dele): nenhum pode ser em memória em produção.
_DINHEIRO_EM_MEMORIA = (
    LedgerEmMemoria,
    DisputasEmMemoria,
    GarantiasEmMemoria,
    EventosWebhookEmMemoria,
    RepassesEmMemoria,
    AvaliacoesEmMemoria,
)


def exigir_dinheiro_no_banco(contexto: Contexto) -> None:
    """Recusa subir se algum repositório de dinheiro for em memória (reiniciar perde dinheiro)."""
    for nome in ("ledger", "disputas", "garantias", "eventos_webhook", "repasses", "avaliacoes"):
        if isinstance(getattr(contexto, nome), _DINHEIRO_EM_MEMORIA):
            raise RuntimeError(f"Repositório de dinheiro em memória em produção: {nome}.")


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
            emissor=f"{config.supabase_url.rstrip('/')}/auth/v1" if config.supabase_url else "",
        )
    conversas = ConversasPostgres(banco)
    notificacoes = NotificacoesPostgres(banco)
    execucao = ExecucaoPostgres(banco)
    contexto = Contexto(
        auth=auth,
        pedidos=PedidosPostgres(banco, lambda: segredo_codigos),
        orcamentos=OrcamentosPostgres(banco),
        contratos=ContratosPostgres(banco),
        ledger=LedgerPostgres(banco),
        disputas=DisputasPostgres(banco),
        garantias=GarantiasPostgres(banco),
        eventos_webhook=EventosWebhookPostgres(banco),
        config=ConfigPostgres(banco),
        agora=agora,
        conversas=conversas,
        notificacoes=notificacoes,
        usuarios=usuarios,
        verificacoes=VerificacoesPostgres(banco),
        taxa=TaxaPostgres(banco),
        avaliacoes=AvaliacoesPostgres(banco),
        repasses=RepassesPostgres(banco),
        recusas=RecusasPostgres(banco),
        notas_material=NotasMaterialPostgres(banco, execucao),
        transacao_banco=banco.transacao,
        extras={
            "usuarios": usuarios,
            "execucao": execucao,
            "conversas": conversas,
            "notificacoes": notificacoes,
            "auditoria": AuditoriaPostgres(banco),
            "banco": banco,
        },
    )
    if config.trato_ambiente.strip().lower() == "producao":
        exigir_dinheiro_no_banco(contexto)
    return contexto


def criar_app_da_config(config: Config | None = None) -> FastAPI:
    """O app de produção/desenvolvimento, conforme `TRATO_PERSISTENCIA`."""
    config = config or obter_config()
    modo = config.trato_persistencia.strip().lower()
    if modo not in PERSISTENCIAS:
        raise RuntimeError(f"TRATO_PERSISTENCIA inválido: {modo!r} (use memoria ou postgres).")
    if modo == "memoria":
        return instalar(
            FastAPI(
                title="Trato API", version=__version__, **parametros_docs(config.trato_ambiente)
            )
        )

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

    app = FastAPI(
        title="Trato API",
        version=__version__,
        lifespan=ciclo,
        **parametros_docs(config.trato_ambiente),
    )
    return instalar(app, criar_contexto_postgres(banco, config))
