"""Registro de acesso a partir da requisição (Termos 14.3 e 16.1).

Nunca derruba nem atrasa a resposta com erro: sem repositório (memória), sem a migration ou com
o banco falhando, a requisição segue. O IP vem de `ip_do_cliente`: `X-Forwarded-For` só vale
atrás de proxy de confiança configurado. O aparelho é o que o app declara (não é prova).
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any

from fastapi import Request

from trato.persistencia.acessos import Acesso
from trato.seguranca.cliente import ip_do_cliente

log = logging.getLogger("trato.acessos")
JANELA_MINUTOS = 60  # a mesma da função do banco: repetição dentro dela não grava de novo
_APARELHOS = frozenset({"android", "ios", "web", "desktop", "outro"})
_LIMITE_MEMORIA = 20_000
_vistos: dict[tuple[Any, ...], float] = {}
_trava = threading.Lock()


def _cabecalho(request: Request, nome: str, maximo: int) -> str | None:
    valor = request.headers.get(nome, "").strip()[:maximo]
    return valor if valor and "\x00" not in valor else None


def registrar(request: Request, contexto: Any, usuario_id: str, evento: str = "acesso") -> str:
    repo = contexto.extras.get("acessos")
    if repo is None:
        return "indisponivel"
    try:
        seguranca = getattr(request.app.state, "seguranca", None)
        tipo = (_cabecalho(request, "x-aparelho-tipo", 20) or "").lower()
        acesso = Acesso(
            usuario_id=usuario_id,
            evento=evento,
            ip=ip_do_cliente(request, seguranca.config if seguranca else None),
            aparelho_tipo=tipo if tipo in _APARELHOS else None,
            sistema_operacional=_cabecalho(request, "x-sistema-operacional", 80),
            dispositivo_id=_cabecalho(request, "x-dispositivo-id", 200),
            user_agent=_cabecalho(request, "user-agent", 400),
            app_versao=_cabecalho(request, "x-app-versao", 40),
        )
        # Só o "acesso" comum é poupado aqui, para não ir ao banco a cada requisição.
        chave = (id(repo), usuario_id, acesso.ip, acesso.dispositivo_id)
        agora = time.monotonic()
        if evento == "acesso":
            with _trava:
                if agora - _vistos.get(chave, float("-inf")) < JANELA_MINUTOS * 60:
                    return "repetido"
        resultado = repo.registrar(acesso, JANELA_MINUTOS if evento == "acesso" else 0)
        if evento == "acesso" and resultado in ("registrado", "repetido"):
            with _trava:
                if len(_vistos) >= _LIMITE_MEMORIA:
                    _vistos.clear()
                _vistos[chave] = agora
        return resultado
    except Exception:  # noqa: BLE001 - o registro nunca derruba a requisição
        log.exception("Registro de acesso falhou")
        return "falhou"
