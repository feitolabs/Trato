"""Custo do cartão parcelado, repassado ao cliente (decisão do João, 31/10/2026, CORREÇÃO).

O João NÃO define essa taxa e o Trato NÃO absorve: o cliente paga o custo de parcelamento que o
provedor cobra para aquele número de parcelas, repassado integralmente. Por isso aqui não existe
valor padrão: a tabela `parcelas -> bps` vem da configuração e, ENQUANTO ESTIVER VAZIA, o parcelado
fica desligado (só cartão à vista e Pix). Os números só entram quando o João trouxer a proposta do
provedor (ver `docs/provedores-pagamento.md`).

Base de cálculo (a confirmar com o provedor): o bps incide sobre o valor do serviço, uma vez,
arredondado meio para cima. Se o provedor cobrar sobre o total já com o custo (gross-up), a conta
muda aqui, num lugar só.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from types import MappingProxyType

BPS_TOTAL = 10_000
MAX_PARCELAS = 12


@dataclass(frozen=True)
class OpcaoParcelamento:
    parcelas: int
    custo_centavos: int
    total_centavos: int
    valor_parcela_centavos: int  # a última parcela absorve o resto da divisão


@dataclass(frozen=True)
class ConfigParcelamento:
    custo_bps_por_parcelas: Mapping[int, int] = field(default_factory=dict)

    def __post_init__(self) -> None:
        tabela = dict(self.custo_bps_por_parcelas)
        for parcelas, bps in tabela.items():
            if isinstance(parcelas, bool) or not isinstance(parcelas, int):
                raise ValueError("parcelas deve ser inteiro")
            if isinstance(bps, bool) or not isinstance(bps, int):
                raise ValueError("custo de parcelamento deve ser inteiro (bps)")
            if not 2 <= parcelas <= MAX_PARCELAS or not 0 <= bps <= BPS_TOTAL:
                raise ValueError("custo de parcelamento inválido")
        object.__setattr__(self, "custo_bps_por_parcelas", MappingProxyType(tabela))

    @property
    def ligado(self) -> bool:
        return bool(self.custo_bps_por_parcelas)

    def custo_centavos(self, base_centavos: int, parcelas: int) -> int:
        """Custo repassado para `parcelas` vezes. 1 vez = 0. Parcelamento não configurado: erro."""
        if parcelas == 1:
            return 0
        if parcelas not in self.custo_bps_por_parcelas:
            raise ParcelamentoIndisponivel(f"Parcelamento em {parcelas}x não está disponível.")
        return (base_centavos * self.custo_bps_por_parcelas[parcelas] + BPS_TOTAL // 2) // BPS_TOTAL

    def opcoes(self, base_centavos: int) -> list[OpcaoParcelamento]:
        saida = []
        for parcelas in sorted(self.custo_bps_por_parcelas):
            custo = self.custo_centavos(base_centavos, parcelas)
            total = base_centavos + custo
            saida.append(OpcaoParcelamento(parcelas, custo, total, total // parcelas))
        return saida


class ParcelamentoIndisponivel(ValueError):
    """Pediu parcelas que não estão na tabela (hoje: todas, a tabela está vazia)."""
