"""Dia e mês no horário de Brasília, como intervalos [início, fim) com fuso.

O Brasil não tem horário de verão desde 2019, então o fuso é fixo em UTC-3. Usar um deslocamento
fixo evita depender da base de fusos do sistema (no Windows ela nem vem instalada). O gatilho do
banco que trava o mês fechado usa 'America/Sao_Paulo', que hoje é o mesmo UTC-3.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone

BRASILIA = timezone(timedelta(hours=-3), "BRT")


def dia(d: date) -> tuple[datetime, datetime]:
    inicio = datetime.combine(d, time(0), BRASILIA)
    return inicio, inicio + timedelta(days=1)


def mes(ano: int, numero: int) -> tuple[datetime, datetime]:
    inicio = datetime(ano, numero, 1, tzinfo=BRASILIA)
    fim = datetime(ano + (numero == 12), numero % 12 + 1, 1, tzinfo=BRASILIA)
    return inicio, fim


def mes_de(instante: datetime) -> tuple[int, int]:
    local = instante.astimezone(BRASILIA)
    return local.year, local.month


def ler_mes(texto: str) -> tuple[int, int]:
    """'2026-10' -> (2026, 10). Levanta ValueError se o formato não for AAAA-MM."""
    ano, _, numero = texto.partition("-")
    if len(ano) != 4 or len(numero) != 2 or not ano.isdigit() or not numero.isdigit():
        raise ValueError("Use o mês no formato AAAA-MM.")
    if not 1 <= int(numero) <= 12:
        raise ValueError("Mês inválido.")
    return int(ano), int(numero)
