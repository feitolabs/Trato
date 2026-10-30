"""Custo do meio de pagamento (Stripe) e margem do Trato (decisão D4, tarefa F4.3).

Regras:
- Tudo em ``int`` de centavos. Percentuais em pontos-base (bps): 3,99% = 399. Sem ``float``.
- Nenhuma taxa fica no código: elas chegam em ``ConfigCustoPagamento`` (depois, da tabela de
  configuração do banco).
- Arredondamento: **meio para cima** (half-up) sobre o percentual, uma única vez por cobrança:
  ``custo_percentual = (valor * bps + 5000) // 10000``. A parte fixa em centavos é somada depois.
  O adicional de parcelamento (bps) soma ao percentual do cartão *antes* de arredondar.
- O custo é calculado sobre o valor cobrado do cliente.
- A taxa do Trato entra já calculada (a progressiva depende de P2).
- Premissa (a confirmar em P3): o profissional recebe ``valor - taxa_trato`` e o custo do
  Stripe sai da taxa do Trato. Logo, ``margem_trato = taxa_trato - custo_stripe`` e pode ser
  negativa (é exatamente o alerta de margem que a decisão D4 pede).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from types import MappingProxyType

BPS_TOTAL = 10_000


class MeioPagamento(StrEnum):
    PIX = "pix"
    CARTAO = "cartao"


@dataclass(frozen=True)
class TaxaMeio:
    """Taxa de um meio: percentual (bps) mais valor fixo (centavos) por cobrança."""

    percentual_bps: int
    fixo_centavos: int = 0

    def __post_init__(self) -> None:
        if self.percentual_bps < 0 or self.fixo_centavos < 0:
            raise ValueError("taxa não pode ser negativa")


@dataclass(frozen=True)
class ConfigCustoPagamento:
    """Taxas do Stripe por meio. Vêm da configuração, nunca do código."""

    pix: TaxaMeio
    cartao: TaxaMeio
    # Adicional em bps por número de parcelas (2..N). Parcelamento sem entrada aqui é recusado.
    adicional_parcelamento_bps: Mapping[int, int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        adicional = dict(self.adicional_parcelamento_bps)
        for parcelas, bps in adicional.items():
            if parcelas < 2 or bps < 0:
                raise ValueError("adicional de parcelamento inválido")
        object.__setattr__(self, "adicional_parcelamento_bps", MappingProxyType(adicional))


@dataclass(frozen=True)
class ResultadoCusto:
    valor_centavos: int
    custo_stripe_centavos: int
    taxa_trato_centavos: int
    liquido_profissional_centavos: int
    margem_trato_centavos: int


def _percentual_half_up(valor_centavos: int, bps: int) -> int:
    return (valor_centavos * bps + BPS_TOTAL // 2) // BPS_TOTAL


def _exigir_inteiro(valor: object, nome: str) -> None:
    if isinstance(valor, bool) or not isinstance(valor, int):
        raise TypeError(f"{nome} deve ser int (centavos), sem float")


def calcular_custo_stripe(
    valor_centavos: int,
    meio: MeioPagamento,
    config: ConfigCustoPagamento,
    parcelas: int = 1,
) -> int:
    """Custo do Stripe, em centavos, para cobrar ``valor_centavos`` pelo ``meio``."""
    _exigir_inteiro(valor_centavos, "valor_centavos")
    if valor_centavos <= 0:
        raise ValueError("valor deve ser maior que zero")
    _exigir_inteiro(parcelas, "parcelas")
    if parcelas < 1:
        raise ValueError("parcelas deve ser pelo menos 1")

    if meio is MeioPagamento.PIX:
        if parcelas != 1:
            raise ValueError("Pix não tem parcelamento")
        taxa = config.pix
        bps = taxa.percentual_bps
    else:
        taxa = config.cartao
        bps = taxa.percentual_bps
        if parcelas > 1:
            if parcelas not in config.adicional_parcelamento_bps:
                raise ValueError(f"parcelamento em {parcelas}x não configurado")
            bps += config.adicional_parcelamento_bps[parcelas]

    return _percentual_half_up(valor_centavos, bps) + taxa.fixo_centavos


def calcular_margem(
    valor_centavos: int,
    meio: MeioPagamento,
    taxa_trato_centavos: int,
    config: ConfigCustoPagamento,
    parcelas: int = 1,
) -> ResultadoCusto:
    """Custo do Stripe, líquido do profissional e quanto sobra para o Trato."""
    custo = calcular_custo_stripe(valor_centavos, meio, config, parcelas)
    _exigir_inteiro(taxa_trato_centavos, "taxa_trato_centavos")
    if not 0 <= taxa_trato_centavos <= valor_centavos:
        raise ValueError("taxa do Trato deve estar entre 0 e o valor")
    return ResultadoCusto(
        valor_centavos=valor_centavos,
        custo_stripe_centavos=custo,
        taxa_trato_centavos=taxa_trato_centavos,
        liquido_profissional_centavos=valor_centavos - taxa_trato_centavos,
        margem_trato_centavos=taxa_trato_centavos - custo,
    )
