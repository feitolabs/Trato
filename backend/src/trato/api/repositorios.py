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
from decimal import ROUND_HALF_UP, Decimal
from typing import Any, Protocol

from trato.api.repositorios_app import (
    OrcamentoDetalhe,
    OrcamentoDoPedido,
    OrcamentoDoProfissional,
    PedidoAberto,
    PrimeiroEnvio,
)
from trato.disputas import ConfigDisputa, Disputa
from trato.financeiro.ledger import Conta, Lancamento, SaldoPedido
from trato.garantias import ConfigGarantia, Garantia, Retrabalho
from trato.pagamentos.idempotencia import RegistroEventos
from trato.pedidos.estados import Evento, Pedido, PrazosPedido


@dataclass(frozen=True)
class ItemOrcamento:
    tipo: str  # deslocamento | horas | material | outro
    descricao: str
    quantidade: Decimal
    valor_unitario_centavos: int

    @property
    def total_centavos(self) -> int:
        """Quantidade x unitário, arredondado para o centavo (meio para cima)."""
        return int(
            (self.quantidade * self.valor_unitario_centavos).to_integral_value(ROUND_HALF_UP)
        )


@dataclass(frozen=True)
class EtapaProposta:
    descricao: str
    valor_centavos: int


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
    prazo_execucao_dias: int | None = None
    garantia_dias: int | None = None  # prometido no orçamento aceito (vence a da categoria)


@dataclass(frozen=True)
class RespostaPedido:
    pergunta_id: str
    resposta: Any


@dataclass(frozen=True)
class PerguntaCategoria:
    """Pergunta que o admin configurou para a categoria (`categoria_perguntas`)."""

    id: str
    texto: str
    tipo: str  # texto | numero | escolha_unica | multipla | sim_nao
    opcoes: tuple[str, ...] = ()
    obrigatoria: bool = False


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
    modalidade: str = "presencial"  # presencial | remoto
    profissional_convidado_id: str | None = None


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


# Termos 12.1: a avaliação vale até N dias após a conclusão (chave `prazo_avaliacao_dias`).
PRAZO_AVALIACAO_PADRAO_DIAS = 30


@dataclass(frozen=True)
class ConfigApi:
    """Valores da tabela de configuração versionada. Nenhum número fixo nas rotas."""

    prazos_pedido: PrazosPedido
    disputas: ConfigDisputa
    garantias: ConfigGarantia
    # Teto de valor do pedido (RN-07). Vazio = ainda não aprovado em Configurações: sem teto.
    valor_maximo_servico_centavos: int | None = None
    # Quantos orçamentos um pedido recebe e em quantos dias o valor é liberado (só exibição).
    limite_orcamentos_por_pedido: int | None = None
    prazo_liberacao_dias: int | None = None
    # Lembretes (5.8): quantas horas antes do fim do prazo; 0 desliga.
    lembrete_confirmacao_antecedencia_horas: int = 12
    lembrete_resposta_disputa_antecedencia_horas: int = 12
    prazo_avaliacao_dias: int = PRAZO_AVALIACAO_PADRAO_DIAS
    # Direito de arrependimento (Termos 7.2; CDC art. 49): nunca menos que 7 dias.
    arrependimento_dias: int = 7
    # Cliente ausente (Termos 7.6 e 7.4): pisos de 20 min e 24 h, teto de 30%.
    ausencia_espera_minutos: int = 20
    ausencia_justificativa_horas: int = 24
    ausencia_retencao_max_bps: int = 3000
    # Ligar depois que o app registrar a chegada: sem ela a ação antiga passa a ser recusada.
    ausencia_exigir_chegada: bool = False
    # Contestação da retenção (Termos 8.7): prazo do cliente e da resposta, em dias úteis.
    ausencia_contestacao_dias_uteis: int = 5
    ausencia_revisao_dias_uteis: int = 10
    # Atendimento (Termos 25.4 e Anexo II): nunca mais que estes prazos.
    sac_resposta_dias_uteis: int = 5
    # Prazo das medidas de cautela de um incidente (9.6): nunca mais que 24 h.
    incidente_seguranca_cautela_horas: int = 24
    # Contestação da decisão da disputa (8.7), em dias úteis.
    disputa_contestacao_prazo_dias_uteis: int = 5
    disputa_contestacao_resposta_dias_uteis: int = 10
    sac_dados_pessoais_dias: int = 15
    # A exclusividade passou a ser do cliente (13.6): a paga pelo profissional não é oferecida.
    exclusividade_profissional_ofertada: bool = False


class ProvedorConfig(Protocol):
    def carregar(self) -> ConfigApi: ...

    def parametro_inteiro(self, chave: str) -> int | None:
        """Parâmetro publicado que não faz parte de `ConfigApi`; `None` se não houver."""


class RepositorioPedidos(Protocol):
    def categoria_aceita_remoto(self, categoria_id: str) -> bool:
        """O admin liberou o serviço remoto nesta categoria?"""

    def obter(self, pedido_id: str) -> Pedido | None: ...

    def salvar(
        self, pedido: Pedido, evento: Evento | None = None, dados: DadosPedido | None = None
    ) -> Pedido:
        """Grava o pedido e, se vier, o evento de auditoria (mesma transação).

        Devolve o pedido como ficou gravado (o Postgres refaz os códigos de início e conclusão
        a partir do segredo do servidor). `dados` só vale ao criar o pedido.
        """

    def eventos(self, pedido_id: str) -> Sequence[Evento]: ...

    def dados_do_pedido(self, pedido_id: str) -> DadosPedido | None:
        """O que o cliente descreveu ao abrir (descrição, faixa de preço, endereço)."""

    def atualizar_dados(self, pedido_id: str, ator_id: str, novos: DadosPedido) -> DadosPedido:
        """Troca esses dados (só o cliente, só enquanto aguarda orçamentos)."""

    def listar_do_usuario(
        self, usuario_id: str, como_cliente: bool, limite: int = 100, offset: int = 0
    ) -> Sequence[Pedido]: ...

    def listar_abertos(
        self, profissional_id: str, limite: int = 100, offset: int = 0
    ) -> Sequence[PedidoAberto]:
        """Pedidos que ainda recebem orçamentos e combinam com o profissional."""


class RepositorioOrcamentos(Protocol):
    def obter(self, orcamento_id: str) -> Orcamento | None: ...

    def do_pedido(self, pedido_id: str) -> Sequence[OrcamentoDoPedido]:
        """Orçamentos enviados (e o aceito) do pedido, o mais barato primeiro."""

    def detalhe(self, orcamento_id: str) -> OrcamentoDetalhe | None:
        """Orçamento com itens, validade e fora do escopo; rascunho nunca é devolvido."""

    def do_profissional(self, profissional_id: str) -> Sequence[OrcamentoDoProfissional]:
        """Última versão de cada orçamento que o profissional enviou, o mais novo primeiro."""

    def primeiros_envios(self, profissional_id: str, desde: datetime) -> Sequence[PrimeiroEnvio]:
        """Por pedido, o primeiro envio do profissional (de `desde` em diante); selo de resposta."""

    def enviar(
        self,
        *,
        pedido_id: str,
        profissional_id: str,
        itens: Sequence[ItemOrcamento],
        agora: datetime,
        etapas: Sequence[EtapaProposta] = (),
        prazo_execucao_dias: int | None = None,
        validade_ate: datetime | None = None,
        garantia_dias: int | None = None,
        fora_do_escopo: str | None = None,
        sinal_material_centavos: int | None = None,
        observacoes: str | None = None,
    ) -> str: ...

    def recusar(self, pedido_id: str, orcamento_id: str) -> bool:
        """Marca o orçamento enviado como `recusado`. Devolve True se mudou agora."""


class RepositorioContratos(Protocol):
    def obter_do_pedido(self, pedido_id: str) -> Contrato | None: ...

    def salvar(self, contrato: Contrato) -> Sequence[tuple[str, str]]:
        """Aceita o orçamento, gera o contrato e recusa os demais orçamentos `enviado` do pedido
        na mesma transação. Devolve `(orcamento_id, profissional_id)` dos recusados agora."""

    def encerrar_por_pagamento_expirado(self, pedido_id: str) -> bool:
        """Cancela o contrato vigente sem dinheiro e vence o orçamento dele. False: nada
        mudou (sem contrato, com dinheiro ou banco ainda sem a migration)."""


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

    def listar(self) -> Sequence[tuple[str, Disputa]]: ...


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
