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


# Devolução de gasto: tipo -> (começo da chave do gasto, começo da chave da devolução).
_DEVOLUCOES = {
    "estorno": ("uso:", "estorno-uso:"),
    "exclusividade_estorno": ("exclusividade-uso:", "exclusividade-estorno:"),
}


@dataclass
class _Lote:
    """Crédito, com quanto do que sobra nele é "do encerramento"."""

    criada_em: datetime
    expira_em: datetime | None
    resto: int
    do_encerramento: int


@dataclass
class _Tirado:
    """Unidades do encerramento que um gasto tirou (cada uma volta uma vez só)."""

    chave: str
    expira_em: datetime | None
    quantidade: int


def vencido_sem_uso(lancamentos: Iterable[Any], inicio: datetime, agora: datetime) -> int:
    """Restauração dos Tratinhos guardados (13.10, I.11): a MESMA regra da função SQL
    `moedas_restauracao_devida` (migration 20261127133600; o cabeçalho dela descreve).

    São do encerramento os créditos que existiam em `inicio` e a devolução posterior de um gasto
    deles com a validade original. Gasto em crédito misto tira primeiro o que não é do
    encerramento. Devido = o que sobrou deles e venceu entre `inicio` e `agora`.
    """
    fim = max(agora, inicio)
    lotes: list[_Lote] = []
    tirados: list[_Tirado] = []
    devendo = 0
    ordenados = sorted(
        lancamentos, key=lambda x: (x.criada_em, x.quantidade < 0, x.chave_idempotencia)
    )
    for item in ordenados:
        if item.quantidade > 0:
            pago = min(item.quantidade, devendo)
            devendo -= pago
            origem = 0
            if item.criada_em <= inicio:
                origem = item.quantidade
            elif item.tipo in _DEVOLUCOES and item.expira_em is not None:
                origem = _devolvido_do_encerramento(item, tirados)
            resto = item.quantidade - pago
            lotes.append(_Lote(item.criada_em, item.expira_em, resto, min(origem, resto)))
            continue
        falta, quando = -item.quantidade, item.criada_em
        validos = sorted(
            (c for c in lotes if c.expira_em is None or c.expira_em > quando), key=_ordem_de_uso
        )
        vencidos = sorted(
            (c for c in lotes if c.expira_em is not None and c.expira_em <= quando),
            key=_ordem_de_uso,
            reverse=True,
        )
        for lote in (*validos, *vencidos):
            tirado = min(lote.resto, falta)
            if tirado:
                parte = max(tirado - (lote.resto - lote.do_encerramento), 0)
                if parte:
                    lote.do_encerramento -= parte
                    tirados.append(_Tirado(item.chave_idempotencia, lote.expira_em, parte))
                lote.resto -= tirado
                falta -= tirado
            if not falta:
                break
        devendo += falta
    return sum(
        c.do_encerramento for c in lotes if c.expira_em is not None and inicio < c.expira_em <= fim
    )


def _devolvido_do_encerramento(item: Any, tirados: list[_Tirado]) -> int:
    de, para = _DEVOLUCOES[item.tipo]
    origem = 0
    for gasto in tirados:
        if origem == item.quantidade:
            break
        if gasto.expira_em != item.expira_em or not gasto.chave.startswith(de):
            continue
        base = para + gasto.chave[len(de) :]
        if item.chave_idempotencia == base or item.chave_idempotencia.startswith(base + ":"):
            parte = min(gasto.quantidade, item.quantidade - origem)
            gasto.quantidade -= parte
            origem += parte
    return origem


def creditos_validos(lancamentos: Iterable[Any], agora: datetime) -> list[Parcela]:
    """O que ainda pode ser usado, com a validade de cada crédito, na ordem de uso."""
    creditos, _ = _processar(lancamentos)
    validos = [c for c in creditos if c.resto > 0 and (c.expira_em is None or c.expira_em > agora)]
    return [Parcela(c.resto, c.expira_em) for c in sorted(validos, key=_ordem_de_uso)]


def parcelas_do_gasto(lancamentos: Iterable[Any], chave: str) -> list[Parcela]:
    """De quais validades saiu o gasto `chave`, na ordem em que foi consumido."""
    return _processar(lancamentos)[1].get(chave, [])
