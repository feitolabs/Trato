"""App em memória com a segurança instalada, relógio e tempo controlados."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

from fastapi.testclient import TestClient

from trato.api import Contexto, criar_app
from trato.api.auth import PapelUsuario, ProvedorAuthFalso, Usuario
from trato.api.memoria import (
    ConfigEmMemoria,
    ContratosEmMemoria,
    DisputasEmMemoria,
    EventosWebhookEmMemoria,
    GarantiasEmMemoria,
    LedgerEmMemoria,
    OrcamentosEmMemoria,
    PedidosEmMemoria,
)
from trato.api.repositorios import ConfigApi
from trato.disputas import ConfigDisputa
from trato.garantias import ConfigGarantia
from trato.lgpd.memoria import FonteDadosEmMemoria, criar_repositorios_memoria
from trato.pedidos.estados import PrazosPedido
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.contadores import Contadores
from trato.seguranca.instalacao import instalar_seguranca

AGORA = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)
CLIENTE = Usuario("cli-1", PapelUsuario.CLIENTE)
OUTRO = Usuario("cli-2", PapelUsuario.CLIENTE)
EQUIPE = Usuario("eq-1", PapelUsuario.EQUIPE)
TOKENS = {"t-cli": CLIENTE, "t-outro": OUTRO, "t-equipe": EQUIPE}


def cab(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@dataclass
class Relogio:
    """Serve de `contexto.agora` (datetime) e de relógio dos contadores (segundos)."""

    agora: datetime = AGORA

    def __call__(self) -> datetime:
        return self.agora

    def segundos(self) -> float:
        return self.agora.timestamp()

    def avancar(self, **kwargs: int) -> None:
        self.agora += timedelta(**kwargs)


@dataclass
class Amb:
    cliente: TestClient
    app: Any
    contexto: Contexto
    relogio: Relogio
    fonte: FonteDadosEmMemoria

    @property
    def seg(self):  # type: ignore[no-untyped-def]
        return self.app.state.seguranca

    @property
    def auditoria(self) -> list[str]:
        return self.seg.auditoria_em_memoria.acoes()


def montar(relogio: Relogio | None = None, **config: Any) -> Amb:
    relogio = relogio or Relogio()
    contexto = Contexto(
        auth=ProvedorAuthFalso(TOKENS),
        pedidos=PedidosEmMemoria(),
        orcamentos=OrcamentosEmMemoria([]),
        contratos=ContratosEmMemoria(),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigEmMemoria(
            ConfigApi(
                prazos_pedido=PrazosPedido(
                    receber_orcamentos=timedelta(days=3),
                    pagamento=timedelta(hours=24),
                    tolerancia_comparecimento=timedelta(hours=1),
                    confirmacao_cliente=timedelta(days=7),
                ),
                disputas=ConfigDisputa(48, 5, 72),
                garantias=ConfigGarantia(30, 7),
            )
        ),
        agora=relogio,
    )
    app = criar_app(contexto)
    cfg = ConfigSeguranca(_env_file=None, **config)
    instalar_seguranca(app, cfg, contadores=Contadores(relogio.segundos))
    fonte = FonteDadosEmMemoria()
    contexto.extras["lgpd"] = criar_repositorios_memoria(fonte)
    # fixa o relógio de segurança no mesmo tempo do teste
    app.state.seguranca.agora = relogio
    return Amb(TestClient(app), app, contexto, relogio, fonte)
