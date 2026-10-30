"""Interface do provedor de pagamento e os tipos que ela troca com o resto do sistema.

Tudo em centavos inteiros. O provedor só cobra, consulta, estorna e prova que um webhook é
dele; quem decide o que o pedido faz com isso é o orquestrador (`pagamentos/orquestrador.py`).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Protocol

from trato.pagamentos.custo import MeioPagamento


class ErroProvedor(Exception):
    """O provedor recusou, não respondeu ou foi mal configurado."""


class StatusCobranca(StrEnum):
    AGUARDANDO = "aguardando"
    PAGA = "paga"
    FALHOU = "falhou"
    CANCELADA = "cancelada"


class TipoEvento(StrEnum):
    """Eventos que o Trato entende, já traduzidos do formato do provedor."""

    PAGAMENTO_CONFIRMADO = "pagamento_confirmado"
    PAGAMENTO_FALHOU = "pagamento_falhou"
    ESTORNO_CONFIRMADO = "estorno_confirmado"
    LIQUIDACAO = "liquidacao"  # o provedor liquidou o valor ao profissional (caminho A)


@dataclass(frozen=True)
class CobrancaProvedor:
    id: str
    valor_centavos: int
    meio: MeioPagamento
    status: StatusCobranca
    metadados: Mapping[str, str] = field(default_factory=dict)
    # Pix: texto "copia e cola". Cartão: segredo do cliente para o app confirmar com o SDK.
    instrucao: str | None = None


@dataclass(frozen=True)
class EstornoProvedor:
    id: str
    cobranca_id: str
    valor_centavos: int
    confirmado: bool


@dataclass(frozen=True)
class EventoProvedor:
    id: str
    tipo: TipoEvento
    cobranca_id: str | None
    valor_centavos: int | None
    metadados: Mapping[str, str]
    pedido_id: str | None = None
    bruto: Mapping[str, Any] = field(default_factory=dict)
    # Id do objeto do evento no provedor (PaymentIntent, transferência, payout): na liquidação é
    # o que liga o aviso ao repasse correspondente (M5).
    objeto_id: str | None = None


class ProvedorPagamento(Protocol):
    nome: str

    def criar_cobranca(
        self,
        *,
        valor_centavos: int,
        meio: MeioPagamento,
        chave_idempotencia: str,
        metadados: Mapping[str, str],
        parcelas: int = 1,
    ) -> CobrancaProvedor:
        """Cria a cobrança. A mesma `chave_idempotencia` devolve a mesma cobrança."""

    def consultar_cobranca(self, cobranca_id: str) -> CobrancaProvedor: ...

    def estornar(
        self, cobranca_id: str, valor_centavos: int | None, chave_idempotencia: str
    ) -> EstornoProvedor:
        """Devolve ao cliente `valor_centavos` (ou tudo, se `None`). Idempotente pela chave."""

    def segredo_webhook(self) -> str:
        """Segredo com que o provedor assina os webhooks (vem do .env, nunca do código)."""

    def validar_webhook(
        self, corpo: bytes, cabecalho: str | None, agora: int | None = None
    ) -> EventoProvedor:
        """Confere a assinatura e devolve o evento. Levanta `AssinaturaInvalida`."""

    def interpretar_evento(self, payload: Mapping[str, Any]) -> EventoProvedor | None:
        """Traduz o JSON de um evento já autenticado. `None` para tipos que não interessam."""
