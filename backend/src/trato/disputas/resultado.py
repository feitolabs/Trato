"""Decisão da disputa e divisão do valor congelado. Só int (centavos e bps), nada de float."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum

from trato.disputas.erros import ResultadoInvalido

BPS_TOTAL = 10_000  # 100% em pontos-base


class Resultado(StrEnum):
    LIBERAR_TUDO = "liberar_tudo"  # tudo ao profissional
    REEMBOLSO_TOTAL = "reembolso_total"  # tudo ao cliente
    REEMBOLSO_PARCIAL = "reembolso_parcial"
    NOVA_VISITA = "nova_visita"  # outro profissional refaz; valor segue retido


@dataclass(frozen=True)
class Decisao:
    resultado: Resultado
    # Só para REEMBOLSO_PARCIAL: informe exatamente um dos dois.
    percentual_cliente_bps: int | None = None  # 1..9999 (2500 = 25%)
    valor_cliente_centavos: int | None = None  # 1..valor_congelado-1


@dataclass(frozen=True)
class Divisao:
    para_profissional: int
    para_cliente: int
    retido: int  # segue congelado (só em NOVA_VISITA)


def _eh_int(x: object) -> bool:
    return isinstance(x, int) and not isinstance(x, bool)


def dividir_valor(valor_congelado: int, decisao: Decisao) -> Divisao:
    """Quanto vai a cada lado. A soma das três partes é sempre `valor_congelado`.

    Arredondamento (parcial por bps): reembolso ao cliente = valor * bps // 10000
    (piso). O resto, inclusive a fração de centavo, fica com o profissional.
    Parcial por valor: o cliente recebe exatamente o valor pedido.
    Parcial exige resultado estritamente entre 0 e o total; use LIBERAR_TUDO ou
    REEMBOLSO_TOTAL nos extremos.
    NOVA_VISITA: nada é pago agora; o valor inteiro segue retido (quem paga a nova
    visita e como o valor é reaproveitado fica a cargo do fluxo de pedidos).
    """
    if not _eh_int(valor_congelado) or valor_congelado <= 0:
        raise ResultadoInvalido("valor congelado deve ser inteiro > 0 (centavos)")
    r = decisao.resultado
    tem_parcial = (
        decisao.percentual_cliente_bps is not None or decisao.valor_cliente_centavos is not None
    )
    if r is not Resultado.REEMBOLSO_PARCIAL:
        if tem_parcial:
            raise ResultadoInvalido("percentual/valor só valem em reembolso parcial")
        if r is Resultado.LIBERAR_TUDO:
            return Divisao(valor_congelado, 0, 0)
        if r is Resultado.REEMBOLSO_TOTAL:
            return Divisao(0, valor_congelado, 0)
        return Divisao(0, 0, valor_congelado)

    bps, valor = decisao.percentual_cliente_bps, decisao.valor_cliente_centavos
    if (bps is None) == (valor is None):
        raise ResultadoInvalido("reembolso parcial exige percentual em bps OU valor, não ambos")
    if bps is not None:
        if not _eh_int(bps) or not 0 < bps < BPS_TOTAL:
            raise ResultadoInvalido("percentual deve ser inteiro entre 1 e 9999 bps")
        cliente = valor_congelado * bps // BPS_TOTAL
        if cliente == 0:
            raise ResultadoInvalido("percentual resulta em reembolso de 0 centavos")
    else:
        if not _eh_int(valor) or not 0 < valor < valor_congelado:
            raise ResultadoInvalido("valor do reembolso deve ficar entre 1 e valor congelado - 1")
        cliente = valor
    return Divisao(valor_congelado - cliente, cliente, 0)
