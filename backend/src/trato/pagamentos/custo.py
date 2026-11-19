"""Custo do meio de pagamento (Stripe) (decisão D4, tarefa F4.3).

Regras:
- Tudo em ``int`` de centavos. Percentuais em pontos-base (bps): 3,99% = 399. Sem ``float``.
- Nenhuma taxa fica no código: elas chegam em ``ConfigCustoPagamento`` (depois, da tabela de
  configuração do banco).
- Arredondamento: **meio para cima** (half-up) sobre o percentual, uma única vez por cobrança:
  ``custo_percentual = (valor * bps + 5000) // 10000``. A parte fixa em centavos é somada depois.
  O adicional de parcelamento (bps) soma ao percentual do cartão *antes* de arredondar.
- O custo é calculado sobre o valor cobrado do cliente.
- O Trato é gratuito (sem taxa): o custo do Pix e do cartão à vista é do Trato.
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


# ESTIMATIVAS (P7), até haver proposta comercial: Pix 1,19%; cartão 3,99% + R$ 0,39; adicional de
# parcelamento chutado. Só alimentam a estimativa de custo mostrada ao profissional.
CUSTO_PROVEDOR_ESTIMADO = ConfigCustoPagamento(
    pix=TaxaMeio(percentual_bps=119),
    cartao=TaxaMeio(percentual_bps=399, fixo_centavos=39),
    adicional_parcelamento_bps={3: 150, 6: 300},
)
