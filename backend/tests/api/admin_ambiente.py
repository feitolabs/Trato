"""Ambiente da API administrativa em memória: equipe com todos os papéis, auth falso, relógio fixo.

Os testes importam a fixture `adm` daqui (`from admin_ambiente import adm  # noqa: F401`).
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from trato import disputas
from trato.api import Contexto, criar_app
from trato.api.admin import AdminContexto, instalar_admin
from trato.api.admin.memoria import (
    AuditoriaEmMemoria,
    ConfigAdminEmMemoria,
    EquipeEmMemoria,
    PedidosAdminEmMemoria,
    UsuariosAdminEmMemoria,
    VerificacoesAdminEmMemoria,
)
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import (
    DadosPessoaisAdmin,
    DefinicaoConfig,
    DocumentoAdmin,
    FaixaTaxa,
    MembroEquipe,
    ParametroConfig,
    UsuarioAdmin,
    VerificacaoAdmin,
)
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
from trato.api.repositorios import ConfigApi, Contrato
from trato.disputas import ConfigDisputa
from trato.financeiro.ledger import registrar_cobranca
from trato.garantias import ConfigGarantia
from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Evento,
    MotivoDisputa,
    Pedido,
    PrazosPedido,
    ProvaDisputa,
)
from trato.pedidos.estados import Papel as PapelPedido

AGORA = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)
PEDIDO = "ped-1"
CLIENTE = Usuario("cli-1", PapelUsuario.CLIENTE)
PROFISSIONAL = Usuario("pro-1", PapelUsuario.PROFISSIONAL)

# papel -> (alçada em centavos). Ninguém tem alçada por padrão: tudo vai para segunda pessoa.
ALCADAS = {"mediador": 200_000, "mediador_sem_alcada": 0, "lider_suporte": 500_000}

DEFINICOES = (
    DefinicaoConfig("adiantamento_bps", "Adiantamento", "bps", 0, 10_000, ("global",), True),
    DefinicaoConfig("prazo_resposta_disputa_horas", "Resposta", "horas", 1, 240),
    DefinicaoConfig("prazo_decisao_disputa_dias_uteis", "Decisão", "dias_uteis", 1, 30),
    DefinicaoConfig("prazo_congelar_disputa_horas", "Congelar", "horas", 1, 720),
    DefinicaoConfig("validade_pedido_horas", "Validade", "horas", 1, 720, ("global", "cidade")),
)
BASE_PARAMETROS = (
    ParametroConfig("adiantamento_bps", 3000),
    ParametroConfig("prazo_resposta_disputa_horas", 48),
    ParametroConfig("prazo_decisao_disputa_dias_uteis", 5),
    ParametroConfig("prazo_congelar_disputa_horas", 72),
)
BASE_FAIXAS = (FaixaTaxa(0, 100_000, 750), FaixaTaxa(100_000, None, 600))  # valores de TESTE


class Relogio:
    def __init__(self) -> None:
        self.agora = AGORA

    def __call__(self) -> datetime:
        return self.agora

    def avancar(self, **kwargs: int) -> None:
        self.agora += timedelta(**kwargs)


class TaxaFalsa:
    def calcular(self, valor_centavos: int) -> int:
        return valor_centavos * 750 // 10_000


class AssinadorFalso:
    def __init__(self) -> None:
        self.chamadas: list[tuple[str, int]] = []

    def assinar(self, caminho: str, segundos: int) -> str:
        self.chamadas.append((caminho, segundos))
        return f"https://storage.exemplo.test/assinada?exp={segundos}"


@dataclass
class AmbienteAdmin:
    cliente: TestClient
    contexto: Contexto
    admin: AdminContexto
    relogio: Relogio
    assinador: AssinadorFalso

    def semear_disputa(
        self,
        valor: int = 100_000,
        *,
        responder: bool = True,
        estado_pedido: Estado = Estado.EM_DISPUTA,
    ) -> None:
        """Pedido em disputa com o dinheiro retido no ledger e a disputa em análise."""
        pedido = Pedido(
            id=PEDIDO,
            cliente_id=CLIENTE.id,
            aberto_em=AGORA - timedelta(days=3),
            estado=estado_pedido,
            profissional_id=PROFISSIONAL.id,
            orcamento_id="orc-1",
            referencia_pagamento="pi_teste_1",
            codigo_inicio="1234",
            codigo_conclusao="9876",
            concluido_em=AGORA - timedelta(days=1),
            estado_antes_da_disputa=Estado.EM_CONFIRMACAO,
        )
        prova = ProvaDisputa(MotivoDisputa.MAL_FEITO, "Parede manchada")
        evento = Evento(
            PEDIDO, Acao.ABRIR_DISPUTA, Estado.EM_CONFIRMACAO, Estado.EM_DISPUTA,
            Ator(PapelPedido.CLIENTE, CLIENTE.id), AGORA - timedelta(hours=2), prova,
        )  # fmt: skip
        self.contexto.pedidos.salvar(pedido, evento)
        self.contexto.contratos.salvar(
            Contrato(PEDIDO, "orc-1", PROFISSIONAL.id, valor, "pintura", taxa_bps_aplicada=750)
        )
        registrar_cobranca(self.contexto.ledger.livro, PEDIDO, valor, "cob-ped-1", AGORA)
        cfg = self.contexto.config.carregar().disputas
        d = disputas.abrir(
            disputas.Ator.CLIENTE, valor, disputas.Motivo.MAL_FEITO,
            AGORA - timedelta(days=1), AGORA - timedelta(hours=2), cfg,
        )  # fmt: skip
        if responder:
            d = d.responder(disputas.Ator.PROFISSIONAL, AGORA - timedelta(hours=1))
        self.contexto.disputas.salvar(PEDIDO, d)

    def pedido(self) -> Pedido:
        return self.contexto.pedidos.obter(PEDIDO)

    def lancamentos(self):
        return self.contexto.ledger.lancamentos(PEDIDO)


def cab(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def token_de(papel: str) -> str:
    return f"t-{papel}"


@pytest.fixture
def adm() -> AmbienteAdmin:
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
    # Uma conta de equipe por papel + extras para os cenários de segunda pessoa e revogação.
    membros: list[MembroEquipe] = [
        MembroEquipe(f"eq-{p.value}", p, alcada_centavos=ALCADAS.get(p.value)) for p in PapelEquipe
    ]
    membros += [
        MembroEquipe("eq-administrador2", PapelEquipe.ADMINISTRADOR),
        MembroEquipe("eq-lider_baixa", PapelEquipe.LIDER_SUPORTE, alcada_centavos=1_000),
        MembroEquipe("eq-mediador_sem_alcada", PapelEquipe.MEDIADOR, alcada_centavos=0),
        MembroEquipe("eq-revogado", PapelEquipe.ADMINISTRADOR, revogado_em=AGORA),
        MembroEquipe("eq-inativo", PapelEquipe.ADMINISTRADOR, ativo=False),
    ]
    tokens = {
        token_de(m.usuario_id.removeprefix("eq-")): Usuario(m.usuario_id, PapelUsuario.EQUIPE)
        for m in membros
    }
    tokens["t-sem-linha"] = Usuario("eq-sem-linha", PapelUsuario.EQUIPE)  # papel equipe sem linha
    tokens["t-cliente"] = CLIENTE
    tokens["t-prof"] = PROFISSIONAL
    contexto = Contexto(
        auth=ProvedorAuthFalso(tokens),
        pedidos=PedidosEmMemoria(),
        orcamentos=OrcamentosEmMemoria(),
        contratos=ContratosEmMemoria(),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigEmMemoria(config),
        agora=relogio,
        taxa=TaxaFalsa(),
    )
    auditoria = AuditoriaEmMemoria(relogio)
    usuarios = UsuariosAdminEmMemoria(auditoria)
    usuarios.adicionar(
        UsuarioAdmin("cli-1", "Maria Cliente", "ativo", "cliente"),
        DadosPessoaisAdmin("123.456.789-09", "+5531999990000", "1990-01-01", None, None),
    )
    usuarios.adicionar(UsuarioAdmin("pro-1", "João Pintor", "ativo", "profissional"))
    verificacoes = VerificacoesAdminEmMemoria(auditoria, relogio)
    verificacoes.adicionar(
        VerificacaoAdmin(
            "ver-1",
            "pro-1",
            "João Pintor",
            "verificado",
            "enviada",
            AGORA - timedelta(days=1),
            cpf_mascarado="***.***.***-09",
            documentos=(
                DocumentoAdmin("doc-1", "documento_frente"),
                DocumentoAdmin("doc-2", "selfie"),
            ),
        ),  # fmt: skip
        {"doc-1": "bucket-privado/ver-1/frente.jpg", "doc-2": "bucket-privado/ver-1/selfie.jpg"},
    )
    config_admin = ConfigAdminEmMemoria(auditoria, DEFINICOES, relogio)
    assinador = AssinadorFalso()
    admin = AdminContexto(
        equipe=EquipeEmMemoria(membros),
        verificacoes=verificacoes,
        usuarios=usuarios,
        pedidos=PedidosAdminEmMemoria(contexto, usuarios),
        config=config_admin,
        auditoria=auditoria,
        assinador=assinador,
    )
    app = criar_app(contexto)
    instalar_admin(app, admin)
    return AmbienteAdmin(TestClient(app), contexto, admin, relogio, assinador)


def publicar_versao_base(adm: AmbienteAdmin) -> str:
    """Deixa uma versão vigente (proposta por 'financeiro', aprovada pelo administrador)."""
    cfg = adm.admin.config
    versao = cfg.criar_rascunho(
        "eq-financeiro", "Versão inicial de teste", BASE_PARAMETROS, BASE_FAIXAS, None, False
    )
    cfg.enviar_para_aprovacao(versao.id, "eq-financeiro", "Pronta")
    cfg.aprovar(versao.id, "eq-administrador", "Conferi")
    cfg.publicar(versao.id, "eq-administrador", "No ar", adm.relogio())
    return versao.id


__all__ = ["adm", "replace"]
