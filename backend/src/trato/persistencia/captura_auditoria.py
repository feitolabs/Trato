"""Guarda o id do registro de auditoria gravado na requisição atual (cabeçalho `X-Auditoria-Id`)."""

from __future__ import annotations

from contextvars import ContextVar

# Ids gravados durante a requisição atual. A lista é criada pelo middleware (antes da rota rodar) e
# a rota só acrescenta: assim o id chega ao cabeçalho `X-Auditoria-Id` mesmo quando a rota síncrona
# roda em outra thread. Fora de uma requisição (testes, scripts) não há lista e nada acontece.
_IDS_DA_REQUISICAO: ContextVar[list[int] | None] = ContextVar("ids_auditoria", default=None)


def iniciar_captura_de_ids() -> list[int]:
    """Chamado pelo middleware no início de cada requisição."""
    ids: list[int] = []
    _IDS_DA_REQUISICAO.set(ids)
    return ids


def anotar_id_gravado(registro_id: int) -> None:
    ids = _IDS_DA_REQUISICAO.get()
    if ids is not None:
        ids.append(registro_id)


class CabecalhoAuditoria:
    """Middleware ASGI puro: devolve o número do registro de auditoria da ação em `X-Auditoria-Id`.

    Não usa `BaseHTTPMiddleware` de propósito: ele relê o corpo da requisição e quebra o limite de
    tamanho para corpos enviados em pedaços."""

    def __init__(self, app):  # type: ignore[no-untyped-def]
        self.app = app

    async def __call__(self, scope, receive, send):  # type: ignore[no-untyped-def]
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        ids = iniciar_captura_de_ids()

        async def enviar(mensagem):  # type: ignore[no-untyped-def]
            if mensagem["type"] == "http.response.start" and ids:
                cabecalhos = list(mensagem.get("headers", []))
                cabecalhos.append((b"x-auditoria-id", str(ids[-1]).encode("ascii")))
                mensagem = {**mensagem, "headers": cabecalhos}
            await send(mensagem)

        await self.app(scope, receive, enviar)
