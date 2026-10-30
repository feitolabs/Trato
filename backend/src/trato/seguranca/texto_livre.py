"""Texto livre digitado pelo usuário (título, descrição, comentário, etiquetas): limite de tamanho
e mascaramento de contato NA ENTRADA (M9). O chat já mascara; o resto vazava telefone/endereço.

Limites vêm de `ConfigSeguranca` (nada fixo aqui). Estouro de limite vira 422 em português.
"""

from __future__ import annotations

from fastapi import HTTPException

from trato.seguranca.config import ConfigSeguranca, obter_config_seguranca
from trato.seguranca.mascaramento import mascarar


def limpar_texto(
    texto: str, campo: str, max_chars: int, config: ConfigSeguranca | None = None
) -> str:
    """Tira espaços das pontas, recusa texto longo demais e esconde telefone, e-mail, link e rua."""
    limpo = texto.strip()
    if len(limpo) > max_chars:
        raise HTTPException(422, f"{campo.capitalize()}: no máximo {max_chars} caracteres.")
    return mascarar(limpo, config or obter_config_seguranca()).exibido


def limpar_etiquetas(
    etiquetas: list[str], config: ConfigSeguranca | None = None
) -> tuple[str, ...]:
    config = config or obter_config_seguranca()
    if len(etiquetas) > config.etiquetas_max:
        raise HTTPException(422, f"Etiquetas: no máximo {config.etiquetas_max}.")
    saida = [
        limpar_texto(e, "etiqueta", config.etiqueta_max_chars, config)
        for e in etiquetas
        if e.strip()
    ]
    return tuple(saida)
