"""Simulador de margem de contribuição por serviço (V2).

margem = taxa do Trato − custo do provedor − estorno/chargeback esperado − suporte
         − garantia/retrabalho − tributos − incentivo

Premissas (a confirmar em P3): o profissional recebe ``ticket − taxa do Trato`` e o custo do
provedor sai da taxa do Trato. Os custos do provedor vêm de ``ConfigCustoPagamento`` e, até haver
proposta comercial (P7), são ESTIMATIVAS.
Tributos: percentual (bps) sobre a taxa do Trato (receita do Trato), não sobre o ticket.
Chargeback esperado: percentual (bps) do ticket, por método (perda esperada = ticket x taxa).
Tudo em centavos inteiros, sem ``float``; cada percentual é arredondado meio para cima uma vez.
"""

from __future__ import annotations

from dataclasses import dataclass, fields

from trato.margem.regras import RegraTaxa, exigir_inteiro, percentual_half_up
from trato.pagamentos.custo import ConfigCustoPagamento, MeioPagamento, calcular_custo_stripe


@dataclass(frozen=True)
class Metodo:
    """Método de pagamento: Pix, cartão à vista (``parcelas=1``) ou parcelado em N vezes."""

    meio: MeioPagamento
    parcelas: int = 1

    @classmethod
    def pix(cls) -> Metodo:
        return cls(MeioPagamento.PIX)

    @classmethod
    def cartao(cls, parcelas: int = 1) -> Metodo:
        return cls(MeioPagamento.CARTAO, parcelas)

    @property
    def rotulo(self) -> str:
        if self.meio is MeioPagamento.PIX:
            return "Pix"
        return "Cartão à vista" if self.parcelas == 1 else f"Cartão {self.parcelas}x"


@dataclass(frozen=True)
class PremissasCusto:
    """Custos além do provedor. Todos são parâmetros; nada fixo no código."""

    chargeback_bps_pix: int = 0
    chargeback_bps_cartao: int = 0
    suporte_centavos: int = 0
    garantia_centavos: int = 0  # garantia/retrabalho esperado por serviço
    tributos_bps: int = 0  # sobre a taxa do Trato
    incentivo_centavos: int = 0

    def __post_init__(self) -> None:
        for campo in fields(self):
            valor = getattr(self, campo.name)
            exigir_inteiro(valor, campo.name)
            if valor < 0:
                raise ValueError(f"{campo.name} não pode ser negativo")

    def chargeback_bps(self, meio: MeioPagamento) -> int:
        return self.chargeback_bps_pix if meio is MeioPagamento.PIX else self.chargeback_bps_cartao


@dataclass(frozen=True)
class ResultadoMargem:
    bruto_centavos: int
    taxa_trato_centavos: int
    custo_provedor_centavos: int
    liquido_profissional_centavos: int
    chargeback_esperado_centavos: int
    suporte_centavos: int
    garantia_centavos: int
    tributos_centavos: int
    incentivo_centavos: int
    margem_centavos: int
    margem_bps_da_taxa: int | None  # margem / taxa do Trato; None se a taxa é zero
    margem_bps_do_bruto: int  # margem / ticket
    margem_negativa: bool


def _razao_bps(parte: int, total: int) -> int:
    return (2 * parte * 10_000 + total) // (2 * total)


def simular_margem(
    ticket_centavos: int,
    metodo: Metodo,
    regra: RegraTaxa,
    custo_provedor: ConfigCustoPagamento,
    premissas: PremissasCusto | None = None,
) -> ResultadoMargem:
    premissas = premissas or PremissasCusto()
    exigir_inteiro(ticket_centavos, "ticket_centavos")
    if ticket_centavos <= 0:
        raise ValueError("ticket deve ser maior que zero")

    taxa = regra.calcular(ticket_centavos)
    provedor = calcular_custo_stripe(ticket_centavos, metodo.meio, custo_provedor, metodo.parcelas)
    chargeback = percentual_half_up(ticket_centavos, premissas.chargeback_bps(metodo.meio))
    tributos = percentual_half_up(taxa, premissas.tributos_bps)
    margem = (
        taxa
        - provedor
        - chargeback
        - premissas.suporte_centavos
        - premissas.garantia_centavos
        - tributos
        - premissas.incentivo_centavos
    )
    return ResultadoMargem(
        bruto_centavos=ticket_centavos,
        taxa_trato_centavos=taxa,
        custo_provedor_centavos=provedor,
        liquido_profissional_centavos=ticket_centavos - taxa,
        chargeback_esperado_centavos=chargeback,
        suporte_centavos=premissas.suporte_centavos,
        garantia_centavos=premissas.garantia_centavos,
        tributos_centavos=tributos,
        incentivo_centavos=premissas.incentivo_centavos,
        margem_centavos=margem,
        margem_bps_da_taxa=_razao_bps(margem, taxa) if taxa else None,
        margem_bps_do_bruto=_razao_bps(margem, ticket_centavos),
        margem_negativa=margem < 0,
    )
