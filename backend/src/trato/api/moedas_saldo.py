"""Tratinhos: saldo e consumo por crédito, calculados só dos lançamentos imutáveis (Termos 13.4).

Cada gasto consome os créditos válidos no instante dele, o que vence primeiro primeiro (sem prazo
por último). Vencido um crédito, some só o que SOBROU dele: o que já foi gasto não é descontado de
novo, e o vencimento nunca deixa o saldo negativo.

Casos de borda:
- gasto lançado depois de o crédito vencer (reserva feita antes, pagamento confirmado depois):
  consome o crédito vencido mais recente que já existia;
- gasto sem crédito nenhum (dado inconsistente): fica devendo e abate os próximos créditos.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime
from typing import Any


@dataclass
class _Credito:
    criada_em: datetime
    expira_em: datetime | None
    resto: int


@dataclass(frozen=True)
class Parcela:
    """Pedaço de um gasto tirado de um crédito (`expira_em` é a validade daquele crédito)."""

    quantidade: int
    expira_em: datetime | None


def _ordem_de_uso(c: _Credito) -> tuple[bool, float, float]:
    return (
        c.expira_em is None,
        c.expira_em.timestamp() if c.expira_em else 0.0,
        c.criada_em.timestamp(),
    )


def _processar(lancamentos: Iterable[Any]) -> tuple[list[_Credito], dict[str, list[Parcela]]]:
    """(créditos com o que sobrou, parcelas de cada gasto pela chave dele)."""
    creditos: list[_Credito] = []
    gastos: dict[str, list[Parcela]] = {}
    devendo = 0
    # No mesmo instante, o crédito entra antes do gasto; a chave só desempata de forma estável.
    ordenados = sorted(
        lancamentos, key=lambda x: (x.criada_em, x.quantidade < 0, x.chave_idempotencia)
    )
    for item in ordenados:
        if item.quantidade > 0:
            pago = min(item.quantidade, devendo)
            devendo -= pago
            creditos.append(_Credito(item.criada_em, item.expira_em, item.quantidade - pago))
            continue
        falta, quando = -item.quantidade, item.criada_em
        validos = sorted(
            (c for c in creditos if c.expira_em is None or c.expira_em > quando),
            key=_ordem_de_uso,
        )
        vencidos = sorted(
            (c for c in creditos if c.expira_em is not None and c.expira_em <= quando),
            key=_ordem_de_uso,
            reverse=True,
        )
        parcelas = gastos.setdefault(item.chave_idempotencia, [])
        for credito in (*validos, *vencidos):
            tirado = min(credito.resto, falta)
            if tirado:
                credito.resto -= tirado
                falta -= tirado
                parcelas.append(Parcela(tirado, credito.expira_em))
            if not falta:
                break
        devendo += falta
    return creditos, gastos


def saldo_disponivel(lancamentos: Iterable[Any], agora: datetime) -> int:
    """O que sobra nos créditos ainda válidos em `agora`. Nunca negativo."""
    creditos, _ = _processar(lancamentos)
    return sum(c.resto for c in creditos if c.expira_em is None or c.expira_em > agora)


def creditos_validos(lancamentos: Iterable[Any], agora: datetime) -> list[Parcela]:
    """O que ainda pode ser usado, com a validade de cada crédito, na ordem de uso."""
    creditos, _ = _processar(lancamentos)
    validos = [c for c in creditos if c.resto > 0 and (c.expira_em is None or c.expira_em > agora)]
    return [Parcela(c.resto, c.expira_em) for c in sorted(validos, key=_ordem_de_uso)]


def parcelas_do_gasto(lancamentos: Iterable[Any], chave: str) -> list[Parcela]:
    """De quais validades saiu o gasto `chave`, na ordem em que foi consumido."""
    return _processar(lancamentos)[1].get(chave, [])
