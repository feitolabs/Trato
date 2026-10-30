"""Registros do fluxo de pagamento (F4.10). Dinheiro em centavos inteiros.

Os repositórios daqui são interfaces; a versão em memória fica em `pagamentos/memoria.py`.
A persistência real (tabelas `pagamentos`, `aditivos`, termos do contrato) vem com a sessão
do banco.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from typing import Protocol

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.taxa import ConfigTaxa


class EstadoCobranca(StrEnum):
    AGUARDANDO = "aguardando"  # criada, o provedor ainda não confirmou
    PAGA = "paga"  # só depois do webhook assinado (D13)
    FALHOU = "falhou"
    CANCELADA = "cancelada"
    DEVOLVIDA = "devolvida"  # pagou fora de hora e o valor voltou ao cliente


class EstadoAditivo(StrEnum):
    PROPOSTO = "proposto"  # profissional pediu; nada é cobrado
    APROVADO = "aprovado"  # cliente aprovou no app; cobrança criada
    RECUSADO = "recusado"  # cliente recusou; nada é cobrado
    PAGO = "pago"  # webhook confirmou


@dataclass(frozen=True)
class CobrancaLocal:
    id: str  # o mesmo id do provedor
    pedido_id: str
    valor_centavos: int
    meio: MeioPagamento
    status: EstadoCobranca
    criada_em: datetime
    aditivo_id: str | None = None
    instrucao: str | None = None
    pago_em: datetime | None = None
    estornado_centavos: int = 0


@dataclass(frozen=True)
class Aditivo:
    id: str
    pedido_id: str
    descricao: str
    valor_centavos: int
    estado: EstadoAditivo
    criado_em: datetime
    aprovado_em: datetime | None = None


@dataclass(frozen=True)
class TermosContrato:
    """Regras congeladas no aceite: mudar a configuração depois não muda este pedido."""

    pedido_id: str
    taxa: ConfigTaxa
    congelado_em: datetime


@dataclass(frozen=True)
class OrdemEstorno:
    """Intenção de devolver dinheiro ao cliente, gravada ANTES de chamar o provedor (A7).

    A chave é a de idempotência no provedor: reenviar a mesma ordem nunca devolve duas vezes.
    `pendente` = ainda não confirmada pelo provedor; a reconciliação reenvia.
    """

    chave: str
    pedido_id: str
    cobranca_id: str
    valor_centavos: int
    criada_em: datetime
    estado: str = "pendente"  # pendente | enviada
    provedor_estorno_id: str | None = None


@dataclass(frozen=True)
class ConfigPagamento:
    """Parte da tabela de configuração que o fluxo de pagamento lê."""

    taxa: ConfigTaxa
    alcada_disputa_centavos: int  # acima disso a decisão da disputa pede segunda pessoa


class RepositorioCobrancas(Protocol):
    def obter(self, cobranca_id: str) -> CobrancaLocal | None: ...

    def salvar(self, cobranca: CobrancaLocal) -> None: ...

    def do_pedido(self, pedido_id: str) -> Sequence[CobrancaLocal]: ...


class RepositorioAditivos(Protocol):
    def obter(self, aditivo_id: str) -> Aditivo | None: ...

    def salvar(self, aditivo: Aditivo) -> None: ...

    def do_pedido(self, pedido_id: str) -> Sequence[Aditivo]: ...


class RepositorioOrdensEstorno(Protocol):
    def salvar(self, ordem: OrdemEstorno) -> None: ...

    def pendentes(self, pedido_id: str | None = None) -> Sequence[OrdemEstorno]: ...

    def do_pedido(self, pedido_id: str) -> Sequence[OrdemEstorno]: ...


class RepositorioTermos(Protocol):
    def obter(self, pedido_id: str) -> TermosContrato | None: ...

    def salvar(self, termos: TermosContrato) -> None: ...
