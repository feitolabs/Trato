"""Contestação de cartão (chargeback) avisada pelo provedor.

O cliente contesta a compra no banco dele; o provedor tira o valor do Trato e abre um prazo para
mandar provas. Aqui só se REGISTRA o que o provedor avisou (webhook assinado): status, valor,
prazo e resultado. Quem decide o efeito no ledger é o orquestrador (perdida = o dinheiro voltou
ao cliente, como um estorno feito por fora).

Valores em centavos inteiros.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, Protocol


class StatusContestacao(StrEnum):
    ABERTA = "aberta"  # o Trato precisa mandar provas até o prazo
    EM_ANALISE = "em_analise"  # provas enviadas; o banco do cliente decide
    GANHA = "ganha"  # o valor volta ao Trato
    PERDIDA = "perdida"  # o valor ficou com o cliente
    ENCERRADA = "encerrada"  # aviso sem disputa formal, reembolsada ou evitada

    @property
    def em_aberto(self) -> bool:
        return self in (StatusContestacao.ABERTA, StatusContestacao.EM_ANALISE)


# Status do Stripe (objeto `dispute`) -> status do Trato.
_STATUS_STRIPE = {
    "warning_needs_response": StatusContestacao.ABERTA,
    "needs_response": StatusContestacao.ABERTA,
    "warning_under_review": StatusContestacao.EM_ANALISE,
    "under_review": StatusContestacao.EM_ANALISE,
    "won": StatusContestacao.GANHA,
    "lost": StatusContestacao.PERDIDA,
    "warning_closed": StatusContestacao.ENCERRADA,
    "charge_refunded": StatusContestacao.ENCERRADA,
    "prevented": StatusContestacao.ENCERRADA,
}

# Motivo do Stripe -> texto da tela.
MOTIVOS = {
    "fraudulent": "Cliente diz que não fez a compra",
    "product_not_received": "Cliente diz que o serviço não foi feito",
    "product_unacceptable": "Cliente diz que o serviço ficou ruim",
    "duplicate": "Cobrança em duplicidade",
    "subscription_canceled": "Cobrança depois de cancelar",
    "credit_not_processed": "Reembolso prometido e não feito",
    "unrecognized": "Cliente não reconhece a cobrança",
    "general": "Motivo geral",
}


@dataclass(frozen=True)
class Contestacao:
    provedor_contestacao_id: str
    valor_centavos: int
    status: StatusContestacao
    aberta_em: datetime
    atualizada_em: datetime
    cobranca_id: str | None = None
    pedido_id: str | None = None
    motivo: str | None = None
    prazo_provas: datetime | None = None
    encerrada_em: datetime | None = None
    provedor: str = "stripe"

    @property
    def motivo_legivel(self) -> str:
        return MOTIVOS.get(self.motivo or "", self.motivo or "Sem motivo informado")


def ler_disputa_stripe(objeto: Mapping[str, Any], agora: datetime) -> Contestacao | None:
    """Monta a contestação a partir do objeto `dispute` do Stripe. `None` se faltar o essencial."""
    disputa_id = objeto.get("id")
    valor = objeto.get("amount")
    status = _STATUS_STRIPE.get(str(objeto.get("status")))
    if (
        not isinstance(disputa_id, str)
        or not disputa_id
        or isinstance(valor, bool)
        or not isinstance(valor, int)
        or valor <= 0
        or status is None
    ):
        return None
    detalhes = objeto.get("evidence_details")
    prazo = detalhes.get("due_by") if isinstance(detalhes, dict) else None
    criada = objeto.get("created")
    cobranca = objeto.get("payment_intent")
    metadados = objeto.get("metadata") if isinstance(objeto.get("metadata"), dict) else {}
    return Contestacao(
        provedor_contestacao_id=disputa_id,
        valor_centavos=valor,
        status=status,
        aberta_em=_instante(criada) or agora,
        atualizada_em=agora,
        cobranca_id=cobranca if isinstance(cobranca, str) and cobranca else None,
        pedido_id=metadados.get("pedido_id") or None,
        motivo=str(objeto["reason"]) if objeto.get("reason") else None,
        prazo_provas=_instante(prazo),
        encerrada_em=None if status.em_aberto else agora,
    )


def _instante(valor: Any) -> datetime | None:
    if isinstance(valor, bool) or not isinstance(valor, int) or valor <= 0:
        return None
    return datetime.fromtimestamp(valor, UTC)


def mesclar(antiga: Contestacao | None, nova: Contestacao) -> Contestacao:
    """O aviso novo vale, mas o que só a primeira vez trouxe (abertura, pedido) não se perde."""
    if antiga is None:
        return nova
    return replace(
        nova,
        aberta_em=antiga.aberta_em,
        pedido_id=nova.pedido_id or antiga.pedido_id,
        cobranca_id=nova.cobranca_id or antiga.cobranca_id,
        prazo_provas=nova.prazo_provas or antiga.prazo_provas,
        encerrada_em=antiga.encerrada_em or nova.encerrada_em,
    )


class RepositorioContestacoes(Protocol):
    def obter(self, provedor_contestacao_id: str) -> Contestacao | None: ...

    def salvar(self, contestacao: Contestacao) -> None:
        """Cria ou atualiza pela chave do provedor."""

    def listar(self) -> Sequence[Contestacao]:
        """Todas, da mais nova para a mais antiga."""

    def abertas_do_pedido(self, pedido_id: str) -> Sequence[Contestacao]: ...


class ContestacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Contestacao] = {}

    def obter(self, provedor_contestacao_id: str) -> Contestacao | None:
        return self._itens.get(provedor_contestacao_id)

    def salvar(self, contestacao: Contestacao) -> None:
        self._itens[contestacao.provedor_contestacao_id] = contestacao

    def listar(self) -> Sequence[Contestacao]:
        return tuple(sorted(self._itens.values(), key=lambda c: c.aberta_em, reverse=True))

    def abertas_do_pedido(self, pedido_id: str) -> Sequence[Contestacao]:
        return tuple(c for c in self.listar() if c.pedido_id == pedido_id and c.status.em_aberto)
