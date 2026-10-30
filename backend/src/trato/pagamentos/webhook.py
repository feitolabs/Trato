"""Verificação de assinatura de webhook no formato do Stripe (tarefa F4.5a).

Cabeçalho ``Stripe-Signature``: ``t=<unix>,v1=<hex>[,v1=<hex>...]``.
A assinatura esperada é HMAC-SHA256 de ``"<t>.<payload bruto>"`` com o segredo do webhook.
O segredo vem por parâmetro (lido do .env por quem chama), nunca do código.
"""

from __future__ import annotations

import hashlib
import hmac
import time

TOLERANCIA_PADRAO_SEGUNDOS = 300


class AssinaturaInvalida(Exception):
    """Cabeçalho ausente, malformado ou assinatura que não confere."""


class AssinaturaExpirada(AssinaturaInvalida):
    """Assinatura correta, mas o carimbo de tempo está fora da tolerância."""


def verificar_assinatura(
    payload: bytes,
    cabecalho: str | None,
    segredo: str | bytes,
    *,
    tolerancia_segundos: int = TOLERANCIA_PADRAO_SEGUNDOS,
    agora: int | None = None,
) -> int:
    """Valida a assinatura e devolve o carimbo ``t``. Levanta ``AssinaturaInvalida``."""
    if not segredo:
        raise AssinaturaInvalida("segredo do webhook não configurado")
    if not cabecalho:
        raise AssinaturaInvalida("cabeçalho Stripe-Signature ausente")

    carimbo, assinaturas = _ler_cabecalho(cabecalho)
    chave = segredo.encode() if isinstance(segredo, str) else segredo
    esperada = hmac.new(chave, f"{carimbo}.".encode() + payload, hashlib.sha256).hexdigest()

    # Sem curto-circuito: compara todas as candidatas em tempo constante.
    confere = False
    for candidata in assinaturas:
        if hmac.compare_digest(esperada, candidata):
            confere = True
    if not confere:
        raise AssinaturaInvalida("assinatura não confere")

    agora = int(time.time()) if agora is None else agora
    if abs(agora - carimbo) > tolerancia_segundos:
        raise AssinaturaExpirada("carimbo de tempo fora da tolerância")
    return carimbo


def _ler_cabecalho(cabecalho: str) -> tuple[int, list[str]]:
    carimbo: int | None = None
    assinaturas: list[str] = []
    for parte in cabecalho.split(","):
        chave, separador, valor = parte.strip().partition("=")
        if not separador:
            continue
        if chave == "t":
            try:
                carimbo = int(valor)
            except ValueError as erro:
                raise AssinaturaInvalida("carimbo de tempo inválido") from erro
        elif chave == "v1":
            assinaturas.append(valor)
    if carimbo is None or not assinaturas:
        raise AssinaturaInvalida("cabeçalho malformado")
    return carimbo, assinaturas
