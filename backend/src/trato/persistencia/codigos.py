"""Códigos de 4 dígitos do check-in e do check-out.

O banco guarda só o HASH (com o segredo do servidor): nunca o código legível. O app do cliente
precisa mostrar o código, então o backend o RECALCULA do mesmo segredo, a partir do agendamento.
Quem não tem o segredo (nem o banco, nem o app do profissional) não consegue deduzi-lo.
"""

from __future__ import annotations

import hashlib
import hmac


def _mac(segredo: str, *partes: str) -> bytes:
    return hmac.new(segredo.encode(), "|".join(partes).encode(), hashlib.sha256).digest()


def codigo_do_agendamento(segredo: str, agendamento_id: str, tipo: str) -> str:
    """`tipo`: 'inicio' ou 'conclusao'."""
    numero = int.from_bytes(_mac(segredo, "codigo", agendamento_id, tipo)[:8], "big")
    return f"{numero % 10_000:04d}"


def hash_do_codigo(segredo: str, agendamento_id: str, tipo: str, codigo: str) -> str:
    return _mac(segredo, "hash", agendamento_id, tipo, codigo).hex()
