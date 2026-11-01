"""Regra única da taxa do Trato (piloto, D13): taxa fixa em bps com mínimo em centavos.

Decisão do João (31/10/2026): a taxa é SOMADA ao pedido. O cliente paga serviço + taxa (+ o custo de
parcelamento, se parcelar); o profissional recebe o valor INTEIRO do orçamento; a taxa é a receita
do Trato (e dela sai o custo do provedor no Pix e no cartão à vista). `calcular_taxa` recebe o
valor do SERVIÇO; `montar_total` devolve a conta completa.

Os dois números vêm da configuração, nunca do código. A tabela progressiva (D2) está em
espera até P2; ligá-la sem a implementação é erro, para ninguém cobrar achando que vale.
Arredondamento: meio para cima, uma vez, igual ao de `custo.py`.
"""

from __future__ import annotations

from dataclasses import dataclass

BPS_TOTAL = 10_000


@dataclass(frozen=True)
class ConfigTaxa:
    taxa_bps: int
    taxa_minima_centavos: int
    tabela_progressiva_ligada: bool = False

    def __post_init__(self) -> None:
        for nome in ("taxa_bps", "taxa_minima_centavos"):
            valor = getattr(self, nome)
            if isinstance(valor, bool) or not isinstance(valor, int) or valor < 0:
                raise ValueError(f"{nome} deve ser inteiro >= 0")
        if self.taxa_bps > BPS_TOTAL:
            raise ValueError("taxa_bps não pode passar de 10000 (100%)")


class TaxaNaoCongelada(Exception):
    """O contrato não traz a taxa congelada no aceite: nada de recalcular pela configuração."""


def taxa_congelada(contrato) -> ConfigTaxa:
    """A taxa que o contrato congelou no aceite (a versão de regras dele, `regras_aplicadas`).

    `contrato` é o `Contrato` do domínio. Depois do aceite, toda taxa (disputa, liquidação,
    cancelamento) sai daqui: a configuração vigente só vale para orçamentos novos (A3).
    """
    if contrato is None or contrato.taxa_bps_aplicada is None:
        raise TaxaNaoCongelada("O contrato deste pedido não tem a taxa congelada no aceite.")
    return ConfigTaxa(contrato.taxa_bps_aplicada, contrato.taxa_minima_centavos)


class TabelaProgressivaNaoImplementada(NotImplementedError):
    """D2 em espera: a tabela progressiva depende de P2 (faixas e percentuais)."""


def calcular_taxa(valor_centavos: int, config: ConfigTaxa) -> int:
    """Taxa do Trato sobre `valor_centavos`: max(percentual, mínimo), nunca acima do valor."""
    if isinstance(valor_centavos, bool) or not isinstance(valor_centavos, int):
        raise TypeError("valor_centavos deve ser int (centavos), sem float")
    if valor_centavos <= 0:
        raise ValueError("valor deve ser maior que zero")
    if config.tabela_progressiva_ligada:
        raise TabelaProgressivaNaoImplementada("A tabela progressiva espera a decisão P2.")
    percentual = (valor_centavos * config.taxa_bps + BPS_TOTAL // 2) // BPS_TOTAL
    return min(max(percentual, config.taxa_minima_centavos), valor_centavos)


@dataclass(frozen=True)
class TotalPedido:
    """A conta de um valor de serviço. Centavos; `cobrado = servico + taxa + parcelamento`."""

    servico_centavos: int
    taxa_centavos: int
    custo_parcelamento_centavos: int
    cobrado_centavos: int
    liquido_profissional_centavos: int  # = servico: o profissional recebe o orçamento inteiro
    receita_trato_centavos: int  # = taxa (o custo do parcelamento é do provedor, não do Trato)


def montar_total(
    servico_centavos: int, config: ConfigTaxa, custo_parcelamento_centavos: int = 0
) -> TotalPedido:
    """Taxa SOMADA ao serviço; o custo de parcelamento (já calculado) é repassado por cima."""
    if isinstance(custo_parcelamento_centavos, bool) or not isinstance(
        custo_parcelamento_centavos, int
    ):
        raise TypeError("custo_parcelamento_centavos deve ser int (centavos), sem float")
    if custo_parcelamento_centavos < 0:
        raise ValueError("custo de parcelamento não pode ser negativo")
    taxa = calcular_taxa(servico_centavos, config)
    return TotalPedido(
        servico_centavos=servico_centavos,
        taxa_centavos=taxa,
        custo_parcelamento_centavos=custo_parcelamento_centavos,
        cobrado_centavos=servico_centavos + taxa + custo_parcelamento_centavos,
        liquido_profissional_centavos=servico_centavos,
        receita_trato_centavos=taxa,
    )
