"""Custo do cartão parcelado, repassado ao cliente (decisão do João, 31/10/2026, CORREÇÃO).

O João NÃO define essa taxa e o Trato NÃO absorve: o cliente paga o custo de parcelamento que o
provedor cobra para aquele número de parcelas, repassado integralmente. Por isso aqui não existe
valor padrão: a tabela `parcelas -> bps` vem da configuração e, ENQUANTO ESTIVER VAZIA, o parcelado
fica desligado (só cartão à vista e Pix). Os números só entram quando o João trouxer a proposta do
provedor (ver `docs/provedores-pagamento.md`).

Base de cálculo (a confirmar com o provedor): o bps incide sobre o valor do serviço, uma vez,
arredondado meio para cima. Se o provedor cobrar sobre o total já com o custo (gross-up), a conta
muda aqui, num lugar só.

6.4: a taxa de juros ao mês não é configurada; é a taxa efetiva que as próprias parcelas cobradas
embutem sobre o preço à vista (ver `juros_mensal_bps`). Ela só informa: não muda valor nenhum.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from decimal import Decimal, localcontext
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
    # 6.4: `custo_total_bps` é o percentual ÚNICO configurado sobre a base; a taxa ao mês é
    # `juros_mensal_bps`. `sem_juros`: não há custo nenhum nesta opção.
    custo_total_bps: int
    diferenca_a_vista_centavos: int
    sem_juros: bool
    juros_mensal_bps: int  # 199 = 1,99% ao mês; 0 só quando sem juros


def juros_mensal_bps(base_centavos: int, valores_centavos: tuple[int, ...]) -> int:
    """Taxa efetiva mensal, em bps, que iguala o valor presente das parcelas ao preço à vista.

    Parcelas mensais, a primeira um mês depois da compra (convenção a confirmar com o provedor).
    Arredonda meio para cima. Se há custo, nunca devolve 0 (não pode parecer "sem juros")."""
    total = sum(valores_centavos)
    if base_centavos <= 0 or total <= base_centavos:
        return 0

    with localcontext() as ctx:
        ctx.prec = 40

        def alcanca(bps: int) -> bool:
            """A taxa real é >= (bps - 0,5)?"""
            fator = 1 + (Decimal(bps) - Decimal("0.5")) / BPS_TOTAL
            presente, desconto = Decimal(0), Decimal(1)
            for valor in valores_centavos:
                desconto /= fator
                presente += valor * desconto
            return presente >= base_centavos

        baixo, alto = 0, 1
        while alcanca(alto):
            baixo, alto = alto, alto * 2
        while alto - baixo > 1:
            meio = (baixo + alto) // 2
            if alcanca(meio):
                baixo = meio
            else:
                alto = meio
    return max(baixo, 1)


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
                    juros_mensal_bps(base_centavos, valores),
                )
            )
        return saida


class ParcelamentoIndisponivel(ValueError):
    """Pediu parcelas que não estão na tabela (hoje: todas, a tabela está vazia)."""
