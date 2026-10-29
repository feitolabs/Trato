"""Regras de taxa do Trato para o simulador: taxa única com mínimo ou tabela progressiva.

Tudo em ``int``: centavos e pontos-base (bps; 7,5% = 750). Sem ``float``.
Arredondamento: meio para cima (half-up), uma única vez por cobrança. Na tabela progressiva,
soma-se o valor exato de cada faixa e arredonda-se só no fim.
Em qualquer regra, ``minimo_centavos`` é piso da taxa, e a taxa nunca passa do ticket.
Os percentuais, as faixas e o mínimo são parâmetros: valores reais vêm da configuração (D2/P2).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

BPS_TOTAL = 10_000


def exigir_inteiro(valor: object, nome: str) -> None:
    if isinstance(valor, bool) or not isinstance(valor, int):
        raise TypeError(f"{nome} deve ser int, sem float")


def percentual_half_up(base_centavos: int, bps: int) -> int:
    """``base * bps / 10000`` arredondado meio para cima (funciona também com base negativa)."""
    return (2 * base_centavos * bps + BPS_TOTAL) // (2 * BPS_TOTAL)


@dataclass(frozen=True)
class TaxaUnica:
    """Um percentual único sobre o ticket, com taxa mínima em centavos."""

    percentual_bps: int
    minimo_centavos: int = 0

    def __post_init__(self) -> None:
        exigir_inteiro(self.percentual_bps, "percentual_bps")
        exigir_inteiro(self.minimo_centavos, "minimo_centavos")
        if not 0 <= self.percentual_bps <= BPS_TOTAL or self.minimo_centavos < 0:
            raise ValueError("taxa fora do intervalo válido")

    def calcular(self, ticket_centavos: int) -> int:
        bruta = percentual_half_up(ticket_centavos, self.percentual_bps)
        return min(max(bruta, self.minimo_centavos), ticket_centavos)


class ModoProgressivo(StrEnum):
    # Cada faixa vale só para a fatia do ticket que cai nela (sem "degrau" entre faixas).
    MARGINAL = "marginal"
    # O ticket inteiro paga o percentual da faixa em que cai.
    FAIXA_INTEIRA = "faixa_inteira"


@dataclass(frozen=True)
class Faixa:
    """Faixa da tabela: vale até ``ate_centavos`` (inclusive); ``None`` = sem limite."""

    ate_centavos: int | None
    percentual_bps: int


@dataclass(frozen=True)
class TaxaProgressiva:
    """Tabela progressiva por faixas de ticket, com taxa mínima em centavos."""

    faixas: tuple[Faixa, ...]
    minimo_centavos: int = 0
    modo: ModoProgressivo = ModoProgressivo.MARGINAL

    def __post_init__(self) -> None:
        if not self.faixas:
            raise ValueError("a tabela precisa de ao menos uma faixa")
        exigir_inteiro(self.minimo_centavos, "minimo_centavos")
        if self.minimo_centavos < 0:
            raise ValueError("taxa mínima não pode ser negativa")
        anterior = 0
        for i, faixa in enumerate(self.faixas):
            exigir_inteiro(faixa.percentual_bps, "percentual_bps")
            if not 0 <= faixa.percentual_bps <= BPS_TOTAL:
                raise ValueError("percentual da faixa fora do intervalo válido")
            ultima = i == len(self.faixas) - 1
            if ultima != (faixa.ate_centavos is None):
                raise ValueError("só a última faixa pode (e deve) ser sem limite")
            if faixa.ate_centavos is not None:
                exigir_inteiro(faixa.ate_centavos, "ate_centavos")
                if faixa.ate_centavos <= anterior:
                    raise ValueError("os limites das faixas devem ser crescentes")
                anterior = faixa.ate_centavos

    def calcular(self, ticket_centavos: int) -> int:
        if self.modo is ModoProgressivo.FAIXA_INTEIRA:
            for faixa in self.faixas:
                if faixa.ate_centavos is None or ticket_centavos <= faixa.ate_centavos:
                    bruta = percentual_half_up(ticket_centavos, faixa.percentual_bps)
                    break
        else:
            # soma exata (centavos x bps) e um único arredondamento no fim
            soma = 0
            inicio = 0
            for faixa in self.faixas:
                fim = ticket_centavos if faixa.ate_centavos is None else faixa.ate_centavos
                fatia = max(0, min(ticket_centavos, fim) - inicio)
                soma += fatia * faixa.percentual_bps
                inicio = fim
                if ticket_centavos <= fim:
                    break
            bruta = (2 * soma + BPS_TOTAL) // (2 * BPS_TOTAL)
        return min(max(bruta, self.minimo_centavos), ticket_centavos)


RegraTaxa = TaxaUnica | TaxaProgressiva
