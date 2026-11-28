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
    valor_parcela_centavos: int  # as primeiras; a última absorve o resto da divisão
    valores_parcelas_centavos: tuple[int, ...]  # uma por parcela; a soma é o total
    ultima_parcela_centavos: int
    # 6.4: o único dado que existe é o custo repassado (percentual ÚNICO sobre a base, não é
    # taxa ao mês). `sem_juros`: não há custo nenhum nesta opção.
    custo_total_bps: int
    diferenca_a_vista_centavos: int
    sem_juros: bool


def dividir_em_parcelas(total_centavos: int, parcelas: int) -> tuple[int, ...]:
    """Parcelas iguais, com o resto na última: a soma é sempre o total. Regra do Trato: a
    integração com o provedor ainda não cobra parcelado, então falta confirmar com ele."""
    base = total_centavos // parcelas
    return (base,) * (parcelas - 1) + (total_centavos - base * (parcelas - 1),)


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
            valores = dividir_em_parcelas(total, parcelas)
            saida.append(
                OpcaoParcelamento(
                    parcelas,
                    custo,
                    total,
                    valores[0],
                    valores,
                    valores[-1],
                    self.custo_bps_por_parcelas[parcelas],
                    custo,
                    custo == 0,
                )
            )
        return saida


class ParcelamentoIndisponivel(ValueError):
    """Pediu parcelas que não estão na tabela (hoje: todas, a tabela está vazia)."""
