"""Termos 12.3: o profissional só tem nota exibida (e usada em filtro e ordem) com o número
mínimo de avaliações publicadas. O número vem do parâmetro `nota_minimo_avaliacoes`; sem ele
vale 1, o comportamento de sempre (a escolha de outro valor é do João)."""

from __future__ import annotations

from typing import Any

CHAVE_MINIMO = "nota_minimo_avaliacoes"
MINIMO_PADRAO = 1
# Avaliações que entram na nota; via jsonb para valer também antes da coluna `status` existir.
SQL_PUBLICADA = "coalesce(to_jsonb(a) ->> 'status', 'publicada') = 'publicada'"


def minimo_de_avaliacoes(config: Any) -> int:
    try:
        valor = config.parametro_inteiro(CHAVE_MINIMO)
    except Exception:  # noqa: BLE001 - sem a configuração, vale o padrão
        return MINIMO_PADRAO
    return valor if isinstance(valor, int) and valor > MINIMO_PADRAO else MINIMO_PADRAO


def nota_visivel(nota: float | None, avaliacoes: int, minimo: int) -> float | None:
    """`None` abaixo do mínimo. Com mínimo 1 nada muda: a nota só existe com avaliação."""
    if minimo > MINIMO_PADRAO and avaliacoes < minimo:
        return None
    return nota
