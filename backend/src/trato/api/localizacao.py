"""Privacidade do ponto do pedido (MAP-1): o servidor guarda e devolve só uma grade de ~500 m."""

from __future__ import annotations

GRADE_GRAUS = 0.005  # ~550 m de latitude; a mesma grade para todo pedido (determinístico)


def na_grade(valor: float | None) -> float | None:
    """Ponto encaixado na grade. A mesma entrada dá sempre a mesma saída (sem aleatoriedade)."""
    if valor is None:
        return None
    return round(round(valor / GRADE_GRAUS) * GRADE_GRAUS, 3)
