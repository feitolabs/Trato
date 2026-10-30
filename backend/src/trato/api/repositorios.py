"""Interfaces de repositório (typing.Protocol). Os adaptadores do Supabase vêm depois.

Mapeamento previsto (docs/modelo-de-dados.md): pedidos -> `pedidos` + `pedido_historico`;
contratos -> `contratos`; orçamentos -> `orcamentos`; ledger -> tabelas do ledger; disputas ->
`disputas`; eventos de webhook -> `eventos_webhook` (unique provedor + evento_id).
Valores sempre em centavos inteiros.
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Any, Protocol

from trato.api.repositorios_app import OrcamentoDetalhe, OrcamentoDoPedido, PedidoAberto
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
    # Taxa congelada no aceite (versão de regras do contrato). Toda conta de taxa depois do aceite
    # (disputa, liquidação) usa estes dois números, nunca a configuração vigente (A3).
    taxa_bps_aplicada: int | None = None
    taxa_minima_centavos: int = 0


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
class Repasse:
    """Ordem de liberar ao profissional (tabela `repasses`, D15). Não é saldo nem saque: o
    dinheiro está no parceiro; aqui fica quanto é, a taxa e o que já foi liberado."""

    pedido_id: str
    profissional_id: str
    valor_bruto_centavos: int
    taxa_centavos: int
    valor_liquido_centavos: int
    gatilho: str  # confirmacao_cliente | prazo | etapa_aprovada | decisao_disputa | sinal_material
    chave: str  # idempotência
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    status: str = "agendado"  # agendado | congelado | liberado | estornado
    liberar_em: datetime | None = None
    provedor_transferencia_id: str | None = None  # id da transferência no parceiro (espelho)
    lancamento_id: str | None = None
    liberado_em: datetime | None = None


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

    def listar_abertos(self, profissional_id: str) -> Sequence[PedidoAberto]:
        """Pedidos que ainda recebem orçamentos e combinam com o profissional."""


class RepositorioOrcamentos(Protocol):
    def obter(self, orcamento_id: str) -> Orcamento | None: ...

    def do_pedido(self, pedido_id: str) -> Sequence[OrcamentoDoPedido]:
        """Orçamentos enviados (e o aceito) do pedido, o mais barato primeiro."""

    def detalhe(self, orcamento_id: str) -> OrcamentoDetalhe | None:
        """Orçamento com itens, validade e fora do escopo; rascunho nunca é devolvido."""


class RepositorioContratos(Protocol):
    def obter_do_pedido(self, pedido_id: str) -> Contrato | None: ...

    def salvar(self, contrato: Contrato) -> None: ...


class RepositorioLedger(Protocol):
    def lancar_varios(self, lancamentos: Sequence[Lancamento]) -> Sequence[Lancamento]:
        """Grava todos ou nenhum; chave repetida com os mesmos dados devolve o antigo."""

    def lancamentos(self, pedido_id: str | None = None) -> Sequence[Lancamento]: ...

    def saldo_da_conta(self, conta: Conta, pedido_id: str | None = None) -> int: ...

    def saldos_pedido(self, pedido_id: str, profissional_id: str | None) -> SaldoPedido: ...


class RepositorioRepasses(Protocol):
    def criar(self, repasse: Repasse) -> Repasse:
        """Cria a ordem; a mesma chave devolve a que já existe."""

    def obter(self, repasse_id: str) -> Repasse | None: ...

    def por_chave(self, chave: str) -> Repasse | None: ...

    def por_transferencia(self, provedor_transferencia_id: str) -> Repasse | None: ...

    def do_pedido(self, pedido_id: str) -> Sequence[Repasse]: ...

    def vincular_transferencia(self, repasse_id: str, provedor_transferencia_id: str) -> None: ...

    def marcar_liberado(self, repasse_id: str, lancamento_id: str, em: datetime) -> None:
        """`agendado` -> `liberado`. Já liberado (ou congelado): `ConflitoDeEstado`."""

    def congelar(self, repasse_id: str, disputa_id: str) -> None: ...


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

    def descartar(self, evento: EventoWebhook) -> None:
        """Esquece o evento registrado cujo tratamento falhou (no Postgres, a transação desfaz)."""

    def marcar_revisao(self, evento: EventoWebhook, motivo: str) -> None:
        """Evento assinado mas com divergência (valor, destino): guardado para o financeiro."""

    def em_revisao(self) -> Sequence[tuple[EventoWebhook, str]]: ...

    def listar(self) -> Sequence[EventoWebhook]: ...
