"""Dias úteis: segunda a sexta, menos os feriados recebidos por parâmetro."""

from __future__ import annotations

from datetime import date, timedelta


def eh_dia_util(dia: date, feriados: frozenset[date] = frozenset()) -> bool:
    return dia.weekday() < 5 and dia not in feriados


def somar_dias_uteis(inicio: date, dias: int, feriados: frozenset[date] = frozenset()) -> date:
    """Data `dias` dias úteis depois de `inicio`. Com 0 dias, devolve o próprio `inicio`.

    O dia de `inicio` não conta; se cair em dia não útil, a contagem começa no próximo útil.
    """
    if dias < 0:
        raise ValueError("A quantidade de dias úteis não pode ser negativa.")
    atual = inicio
    restantes = dias
    while restantes > 0:
        atual += timedelta(days=1)
        if eh_dia_util(atual, feriados):
            restantes -= 1
    return atual
