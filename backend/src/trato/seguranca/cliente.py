"""Origem da requisição (IP e dispositivo) para auditoria e limites."""

from __future__ import annotations

from fastapi import Request

from trato.seguranca.config import ConfigSeguranca, obter_config_seguranca


def ip_do_cliente(request: Request, config: ConfigSeguranca | None = None) -> str:
    """IP de quem chamou. `X-Forwarded-For` só vale com `TRATO_SEG_CONFIAR_X_FORWARDED_FOR`
    (atrás de proxy de confiança); aí vale o ÚLTIMO item, o que o proxy acrescentou."""
    config = config or obter_config_seguranca()
    if config.confiar_x_forwarded_for:
        encaminhado = request.headers.get("x-forwarded-for", "")
        if encaminhado.strip():
            return encaminhado.split(",")[-1].strip()
    return request.client.host if request.client else "desconhecido"


def dispositivo_do_cliente(request: Request) -> str | None:
    """Id do aparelho (`X-Dispositivo-Id`) ou, na falta, o user-agent (cortado)."""
    achado = request.headers.get("x-dispositivo-id") or request.headers.get("user-agent")
    return achado.strip()[:200] if achado and achado.strip() else None
