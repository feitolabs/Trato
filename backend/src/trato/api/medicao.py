"""Medidor de performance por requisição: consultas ao banco e tempo gasto.

Ligado com `TRATO_MEDIR_CONSULTAS=1`. Cada resposta ganha o cabeçalho `Server-Timing`
(`db;dur=..;desc="N consultas"`, `total;dur=..`) e uma linha no log `trato.medicao`.
Desligado, não faz nada. Não registra parâmetros nem dados: só rota, contagem e tempo.
"""

from __future__ import annotations

import logging
import os
import time

from trato.persistencia.conexao import MEDICAO, MedicaoConsultas

log = logging.getLogger("trato.medicao")


def medicao_ligada() -> bool:
    return os.environ.get("TRATO_MEDIR_CONSULTAS", "").strip() in {"1", "true", "sim"}


class MedidorConsultas:
    """Middleware ASGI. Usa ContextVar: a medição chega às rotas síncronas (threadpool)."""

    def __init__(self, app):  # type: ignore[no-untyped-def]
        self.app = app

    async def __call__(self, scope, receive, send):  # type: ignore[no-untyped-def]
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        medicao = MedicaoConsultas()
        marca = MEDICAO.set(medicao)
        inicio = time.perf_counter()

        async def enviar(mensagem):  # type: ignore[no-untyped-def]
            if mensagem["type"] == "http.response.start":
                total_ms = (time.perf_counter() - inicio) * 1000
                db_ms = medicao.segundos * 1000
                valor = (
                    f'db;dur={db_ms:.1f};desc="{medicao.consultas} consultas", '
                    f"total;dur={total_ms:.1f}"
                )
                cabecalhos = list(mensagem.get("headers", []))
                cabecalhos.append((b"server-timing", valor.encode()))
                mensagem = {**mensagem, "headers": cabecalhos}
                log.info(
                    "%s %s -> %s | %d consultas | banco %.0f ms | total %.0f ms",
                    scope.get("method"),
                    scope.get("path"),
                    mensagem.get("status"),
                    medicao.consultas,
                    db_ms,
                    total_ms,
                )
            await send(mensagem)

        try:
            await self.app(scope, receive, enviar)
        finally:
            MEDICAO.reset(marca)
