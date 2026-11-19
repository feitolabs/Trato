"""A conta de um valor de serviço. O Trato é 100% gratuito (João, 18/11/2026): não há taxa.

O cliente paga o valor do orçamento (+ o custo de parcelamento do provedor, se parcelar) e o
profissional recebe o orçamento inteiro. O custo do Pix e do cartão à vista é do Trato.
Valores em centavos inteiros.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class TotalPedido:
    """A conta de um valor de serviço. Centavos; `cobrado = servico + parcelamento`."""

    servico_centavos: int
    custo_parcelamento_centavos: int
    cobrado_centavos: int


def montar_total(servico_centavos: int, custo_parcelamento_centavos: int = 0) -> TotalPedido:
    """O que cobrar do cliente: o serviço mais o custo de parcelamento (já calculado)."""
    if isinstance(servico_centavos, bool) or not isinstance(servico_centavos, int):
        raise TypeError("servico_centavos deve ser int (centavos), sem float")
    if servico_centavos <= 0:
        raise ValueError("valor deve ser maior que zero")
    if isinstance(custo_parcelamento_centavos, bool) or not isinstance(
        custo_parcelamento_centavos, int
    ):
        raise TypeError("custo_parcelamento_centavos deve ser int (centavos), sem float")
    if custo_parcelamento_centavos < 0:
        raise ValueError("custo de parcelamento não pode ser negativo")
    return TotalPedido(
        servico_centavos=servico_centavos,
        custo_parcelamento_centavos=custo_parcelamento_centavos,
        cobrado_centavos=servico_centavos + custo_parcelamento_centavos,
    )
