"""Regra única da taxa do Trato (piloto, D13): taxa fixa em bps com mínimo em centavos.

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
