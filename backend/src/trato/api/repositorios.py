"""Interfaces de repositório (typing.Protocol). Os adaptadores do Supabase vêm depois.

Mapeamento previsto (docs/modelo-de-dados.md): pedidos -> `pedidos` + `pedido_historico`;
contratos -> `contratos`; orçamentos -> `orcamentos`; ledger -> tabelas do ledger; disputas ->
`disputas`; eventos de webhook -> `eventos_webhook` (unique provedor + evento_id).
Valores sempre em centavos inteiros.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Protocol

from trato.disputas import ConfigDisputa, Disputa
from trato.financeiro.ledger import Conta, Lancamento, SaldoPedido
from trato.garantias import ConfigGarantia, Garantia, Retrabalho
from trato.pagamentos.idempotencia import RegistroEventos
from trato.pedidos.estados import Evento, Pedido, PrazosPedido


@dataclass(frozen=True)
class Orcamento:
    id: str
    pedido_id: str
    profissional_id: str
    valor_centavos: int
    categoria_id: str | None = None


@dataclass(frozen=True)
class Contrato:
    """Congelado ao aceitar o orçamento. Etapas e aditivos entram na F4.4.

    `aceito_em` e os dados do aparelho são registrados no aceite (só o Postgres os guarda).
    """

    pedido_id: str
    orcamento_id: str
    profissional_id: str
    valor_centavos: int
    categoria_id: str | None = None
    aceito_em: datetime | None = None
    aceite_ip: str | None = None
    aceite_dispositivo: str | None = None


@dataclass(frozen=True)
class RespostaPedido:
    pergunta_id: str
    resposta: Any


@dataclass(frozen=True)
class EnderecoPedido:
    logradouro: str
    numero: str | None = None
    complemento: str | None = None
    bairro: str | None = None
    cep: str | None = None
    referencia: str | None = None
    lat: float | None = None
    lng: float | None = None


@dataclass(frozen=True)
class DadosPedido:
    """O que o cliente descreve ao abrir o pedido. A memória ignora; o Postgres exige."""

    categoria_id: str
    cidade_id: str
    titulo: str
    descricao: str
    bairro: str | None = None
    local_aprox_lat: float | None = None
    local_aprox_lng: float | None = None
    prazo_desejado: date | None = None
    faixa_preco_min_centavos: int | None = None
    faixa_preco_max_centavos: int | None = None
    urgente: bool = False
    respostas: tuple[RespostaPedido, ...] = ()
    endereco: EnderecoPedido | None = None


@dataclass(frozen=True)
class EventoWebhook:
    provedor: str
    evento_id: str
    tipo: str
    payload: dict[str, Any]
    recebido_em: datetime


@dataclass(frozen=True)
class ConfigApi:
    """Valores da tabela de configuração versionada. Nenhum número fixo nas rotas."""

    prazos_pedido: PrazosPedido
    disputas: ConfigDisputa
    garantias: ConfigGarantia


class ProvedorConfig(Protocol):
    def carregar(self) -> ConfigApi: ...


class RepositorioPedidos(Protocol):
    def obter(self, pedido_id: str) -> Pedido | None: ...

    def salvar(
        self, pedido: Pedido, evento: Evento | None = None, dados: DadosPedido | None = None
    ) -> Pedido:
        """Grava o pedido e, se vier, o evento de auditoria (mesma transação).

        Devolve o pedido como ficou gravado (o Postgres refaz os códigos de início e conclusão
        a partir do segredo do servidor). `dados` só vale ao criar o pedido.
        """

    def eventos(self, pedido_id: str) -> Sequence[Evento]: ...

    def listar_do_usuario(self, usuario_id: str, como_cliente: bool) -> Sequence[Pedido]: ...


class RepositorioOrcamentos(Protocol):
    def obter(self, orcamento_id: str) -> Orcamento | None: ...


class RepositorioContratos(Protocol):
    def obter_do_pedido(self, pedido_id: str) -> Contrato | None: ...

    def salvar(self, contrato: Contrato) -> None: ...


class RepositorioLedger(Protocol):
    def lancar_varios(self, lancamentos: Sequence[Lancamento]) -> Sequence[Lancamento]:
        """Grava todos ou nenhum; chave repetida com os mesmos dados devolve o antigo."""

    def lancamentos(self, pedido_id: str | None = None) -> Sequence[Lancamento]: ...

    def saldo_da_conta(self, conta: Conta, pedido_id: str | None = None) -> int: ...

    def saldos_pedido(self, pedido_id: str, profissional_id: str | None) -> SaldoPedido: ...


class RepositorioDisputas(Protocol):
    def obter(self, pedido_id: str) -> Disputa | None: ...

    def salvar(self, pedido_id: str, disputa: Disputa) -> None: ...


class RepositorioGarantias(Protocol):
    def obter_garantia(self, pedido_id: str) -> Garantia | None: ...

    def salvar_garantia(self, pedido_id: str, garantia: Garantia) -> None: ...

    def retrabalhos(self, pedido_id: str) -> Sequence[Retrabalho]: ...

    def salvar_retrabalho(self, pedido_id: str, retrabalho: Retrabalho) -> None: ...


class RepositorioEventosWebhook(RegistroEventos, Protocol):
    """Idempotência (`iniciar/concluir/liberar`, de pagamentos/) + cópia do evento recebido."""

    def registrar(self, evento: EventoWebhook) -> None: ...

    def listar(self) -> Sequence[EventoWebhook]: ...
