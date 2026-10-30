"""Montagem da API com repositórios em memória, auth falso e relógio fixo."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from trato.api import Contexto, criar_app
from trato.api.admin import AdminContexto, instalar_admin
from trato.api.admin.memoria import AuditoriaEmMemoria as AuditoriaAdminEmMemoria
from trato.api.admin.memoria import EquipeEmMemoria
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import MembroEquipe
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
from trato.api.repositorios import ConfigApi, Contrato, Orcamento
from trato.disputas import ConfigDisputa
from trato.financeiro.ledger import registrar_cobranca, repartir_custodia
from trato.garantias import ConfigGarantia
from trato.pedidos.estados import Estado, Pedido, PrazosPedido

AGORA = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)
SEGREDO_WEBHOOK = "valor-de-teste-do-webhook"

CLIENTE = Usuario("cli-1", PapelUsuario.CLIENTE)
OUTRO_CLIENTE = Usuario("cli-2", PapelUsuario.CLIENTE)
PROFISSIONAL = Usuario("pro-1", PapelUsuario.PROFISSIONAL)
OUTRO_PROFISSIONAL = Usuario("pro-2", PapelUsuario.PROFISSIONAL)
EQUIPE = Usuario("eq-1", PapelUsuario.EQUIPE)

# Equipe com papel real na tabela `equipe` (EQUIPE acima, "eq-1", NÃO está na tabela: sem poder).
MEMBROS_EQUIPE = {
    "t-mediador": MembroEquipe("eq-med", PapelEquipe.MEDIADOR, alcada_centavos=10**9),
    "t-financeiro": MembroEquipe("eq-fin", PapelEquipe.FINANCEIRO),
    "t-n1": MembroEquipe("eq-n1", PapelEquipe.ATENDENTE_N1),
    "t-moderador": MembroEquipe("eq-mod", PapelEquipe.MODERADOR),
    "t-juridico": MembroEquipe("eq-jur", PapelEquipe.JURIDICO),
    "t-cadastro": MembroEquipe("eq-cad", PapelEquipe.CADASTRO),
    "t-seguranca": MembroEquipe("eq-seg", PapelEquipe.SEGURANCA),
}

TOKENS = {
    **{t: Usuario(m.usuario_id, PapelUsuario.EQUIPE) for t, m in MEMBROS_EQUIPE.items()},
    "t-cliente": CLIENTE,
    "t-outro-cliente": OUTRO_CLIENTE,
    "t-prof": PROFISSIONAL,
    "t-outro-prof": OUTRO_PROFISSIONAL,
    "t-equipe": EQUIPE,
}


def cab(nome: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {nome}"}


@dataclass
class Relogio:
    agora: datetime = AGORA

    def __call__(self) -> datetime:
        return self.agora

    def avancar(self, **kwargs: int) -> None:
        self.agora += timedelta(**kwargs)


@dataclass
class Ambiente:
    cliente: TestClient
    contexto: Contexto
    relogio: Relogio
    admin: AdminContexto | None = None

    def semear_pedido(self, estado: Estado, **campos) -> Pedido:
        base = Pedido(
            id="ped-1",
            cliente_id=CLIENTE.id,
            aberto_em=AGORA - timedelta(days=1),
            estado=estado,
            profissional_id=PROFISSIONAL.id,
            orcamento_id="orc-1",
        )
        pedido = replace(base, **campos)
        self.contexto.pedidos.salvar(pedido)
        self.contexto.contratos.salvar(
            Contrato(pedido.id, "orc-1", PROFISSIONAL.id, 100_000, "pintura")
        )
        return pedido

    def semear_dinheiro(self, cobrado: int = 100_000, taxa: int | None = None) -> None:
        """Cobrança confirmada (retida); com `taxa`, já repartida entre profissional e Trato."""
        livro = self.contexto.ledger.livro
        registrar_cobranca(livro, "ped-1", cobrado, "cob-ped-1", AGORA)
        if taxa is not None:
            repartir_custodia(livro, "ped-1", PROFISSIONAL.id, taxa, "rep-ped-1", AGORA)


@pytest.fixture
def amb() -> Ambiente:
    relogio = Relogio()
    config = ConfigApi(
        prazos_pedido=PrazosPedido(
            receber_orcamentos=timedelta(days=3),
            pagamento=timedelta(hours=24),
            tolerancia_comparecimento=timedelta(hours=1),
            confirmacao_cliente=timedelta(days=7),
        ),
        disputas=ConfigDisputa(
            prazo_resposta_horas=48, prazo_decisao_dias_uteis=5, prazo_congelar_repasse_horas=72
        ),
        garantias=ConfigGarantia(garantia_dias_padrao=30, prazo_atendimento_dias=7),
    )
    orcamentos = OrcamentosEmMemoria(
        [
            Orcamento("orc-1", "ped-1", PROFISSIONAL.id, 100_000, "pintura"),
            Orcamento("orc-outro", "ped-outro", PROFISSIONAL.id, 5_000),
        ]
    )
    contexto = Contexto(
        auth=ProvedorAuthFalso(TOKENS),
        pedidos=PedidosEmMemoria(),
        orcamentos=orcamentos,
        contratos=ContratosEmMemoria(),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigEmMemoria(config),
        agora=relogio,
        segredo_webhook=lambda: SEGREDO_WEBHOOK,
    )
    app = criar_app(contexto)
    admin = AdminContexto(
        equipe=EquipeEmMemoria(list(MEMBROS_EQUIPE.values())),
        verificacoes=None,  # type: ignore[arg-type]
        usuarios=None,  # type: ignore[arg-type]
        pedidos=None,  # type: ignore[arg-type]
        config=None,  # type: ignore[arg-type]
        auditoria=AuditoriaAdminEmMemoria(relogio),
    )
    instalar_admin(app, admin)
    ambiente = Ambiente(TestClient(app), contexto, relogio)
    ambiente.admin = admin
    return ambiente


def janela_futura() -> dict[str, str]:
    inicio = AGORA + timedelta(days=2)
    return {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
