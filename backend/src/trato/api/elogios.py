"""Elogios em tags (ideia #11): lista fechada e positiva, validação e contagem do perfil.

Constante única: é aqui que se muda a lista ou o máximo por avaliação (sem número solto nas rotas).
"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable, Sequence
from typing import Any

from fastapi import HTTPException

ETIQUETAS_ELOGIO: tuple[str, ...] = (
    "Pontual",
    "Limpo",
    "Explicou bem",
    "Preço justo",
    "Educado",
    "Caprichoso",
)
MAX_ETIQUETAS_POR_AVALIACAO = 3
MAX_ETIQUETAS_TOP_PERFIL = 3


def _chave(texto: str) -> str:
    return " ".join(texto.split()).casefold()


_CANONICAS = {_chave(e): e for e in ETIQUETAS_ELOGIO}


def canonica(texto: str) -> str | None:
    """Valor canônico da etiqueta (ignora espaços repetidos e maiúsculas); None se fora da lista."""
    return _CANONICAS.get(_chave(texto))


def validar_etiquetas_elogio(etiquetas: Sequence[str]) -> tuple[str, ...]:
    """Cliente -> profissional: só a lista fechada, até 3, sem repetir. Vazias são ignoradas."""
    saida: list[str] = []
    for bruta in etiquetas:
        if not bruta.strip():
            continue
        valor = canonica(bruta)
        if valor is None:
            raise HTTPException(
                422, "Etiqueta inválida. Escolha entre: " + ", ".join(ETIQUETAS_ELOGIO) + "."
            )
        if valor in saida:
            raise HTTPException(422, f"Etiqueta repetida: {valor}.")
        saida.append(valor)
    if len(saida) > MAX_ETIQUETAS_POR_AVALIACAO:
        raise HTTPException(
            422, f"Escolha no máximo {MAX_ETIQUETAS_POR_AVALIACAO} etiquetas de elogio."
        )
    return tuple(saida)


def etiquetas_top(avaliacoes: Iterable[Any]) -> list[dict[str, Any]]:
    """Até 3 etiquetas mais usadas: total desc e depois nome. Só contagem, nunca o autor.
    Avaliações antigas com texto livre fora da lista não entram."""
    contagem: Counter[str] = Counter()
    for a in avaliacoes:
        for e in set(filter(None, (canonica(x) for x in a.etiquetas))):
            contagem[e] += 1
    ordenadas = sorted(contagem.items(), key=lambda par: (-par[1], par[0]))
    return [
        {"etiqueta": nome, "total": total} for nome, total in ordenadas[:MAX_ETIQUETAS_TOP_PERFIL]
    ]
