"""Middleware HTTP: cabeçalhos de segurança, tamanho máximo do corpo e limite de taxa.

ASGI puro (sem BaseHTTPMiddleware) para contar os bytes do corpo mesmo quando vêm em pedaços.
Respostas de erro daqui seguem o formato da API: `{"detail": "..."}` em português.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import Awaitable, Callable, MutableMapping
from typing import Any

import anyio.to_thread
from starlette.exceptions import HTTPException

from trato.config import obter_config
from trato.seguranca.estado import Seguranca

Escopo = MutableMapping[str, Any]
Receber = Callable[[], Awaitable[MutableMapping[str, Any]]]
Enviar = Callable[[MutableMapping[str, Any]], Awaitable[None]]

_CAMINHOS_DOCS = ("/docs", "/redoc")


def cabecalhos_seguranca(seg: Seguranca, caminho: str) -> list[tuple[bytes, bytes]]:
    docs = caminho.startswith(_CAMINHOS_DOCS)
    itens = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
        "Cross-Origin-Resource-Policy": "same-site",
    }
    if not docs:  # a página /docs precisa carregar script e estilo próprios
        itens["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
        itens["Cache-Control"] = "no-store"
    ambiente = obter_config().trato_ambiente.lower()
    if ambiente not in ("desenvolvimento", "dev", "local", "teste") and seg.config.hsts_max_age_s:
        itens["Strict-Transport-Security"] = (
            f"max-age={seg.config.hsts_max_age_s}; includeSubDomains"
        )
    return [(k.lower().encode(), v.encode()) for k, v in itens.items()]


def _ip(seg: Seguranca, escopo: Escopo, cabecalhos: dict[bytes, bytes]) -> str:
    if seg.config.confiar_x_forwarded_for:
        encaminhado = cabecalhos.get(b"x-forwarded-for", b"").decode("latin-1")
        if encaminhado.strip():
            return encaminhado.split(",")[-1].strip()
    cliente = escopo.get("client")
    return cliente[0] if cliente else "desconhecido"


def _usuario(seg: Seguranca, cabecalhos: dict[bytes, bytes]) -> str | None:
    bruto = cabecalhos.get(b"authorization", b"").decode("latin-1")
    if bruto.lower().startswith("bearer ") and len(bruto) > 7:
        return seg.hash_opaco(bruto[7:].strip())[:16]
    return None


def _limite_corpo(seg: Seguranca, caminho: str) -> int:
    melhor, limite = -1, seg.config.corpo_max_bytes
    for prefixo, valor in seg.config.corpo_max_por_prefixo.items():
        if caminho.startswith(prefixo) and len(prefixo) > melhor:
            melhor, limite = len(prefixo), valor
    return limite


class MiddlewareProtecao:
    def __init__(self, app: Callable[..., Awaitable[None]], seg: Seguranca, ao_primeiro_uso=None):  # type: ignore[no-untyped-def]
        self.app = app
        self.seg = seg
        self._ao_primeiro_uso = ao_primeiro_uso

    async def __call__(self, escopo: Escopo, receber: Receber, enviar: Enviar) -> None:
        if escopo["type"] != "http":
            await self.app(escopo, receber, enviar)
            return
        if self._ao_primeiro_uso:
            self._ao_primeiro_uso()
        seg = self.seg
        caminho, metodo = escopo["path"], escopo["method"]
        cab = {k.lower(): v for k, v in escopo["headers"]}
        id_requisicao = uuid.uuid4().hex
        extras = [*cabecalhos_seguranca(seg, caminho), (b"x-request-id", id_requisicao.encode())]

        async def enviar_com_cabecalhos(msg: MutableMapping[str, Any]) -> None:
            if msg["type"] == "http.response.start":
                ja = {k.lower() for k, _ in msg.get("headers", [])}
                msg["headers"] = [*msg.get("headers", []), *(h for h in extras if h[0] not in ja)]
            await enviar(msg)

        async def recusar(status: int, texto: str, retry: int | None = None) -> None:
            corpo = json.dumps({"detail": texto}, ensure_ascii=False).encode()
            cabs = [(b"content-type", b"application/json; charset=utf-8")]
            if retry:
                cabs.append((b"retry-after", str(retry).encode()))
            await enviar_com_cabecalhos(
                {"type": "http.response.start", "status": status, "headers": cabs}
            )
            await enviar_com_cabecalhos({"type": "http.response.body", "body": corpo})

        if metodo != "OPTIONS":
            limite = _limite_corpo(seg, caminho)
            declarado = cab.get(b"content-length", b"")
            if declarado.isdigit() and int(declarado) > limite:
                await recusar(413, "Requisição grande demais.")
                return
            if seg.config.limite_taxa_ativo:
                ip = _ip(seg, escopo, cab)
                decisao = seg.limitador.checar(
                    metodo, caminho, seg.hash_opaco(ip), _usuario(seg, cab)
                )
                if not decisao.permitido:
                    await self._registrar_excesso(decisao)
                    await recusar(
                        429,
                        "Muitas tentativas. Aguarde um pouco e tente de novo.",
                        decisao.retry_apos_s,
                    )
                    return
        else:
            limite = seg.config.corpo_max_bytes

        total = 0

        async def receber_limitado() -> MutableMapping[str, Any]:
            nonlocal total
            msg = await receber()
            if msg["type"] == "http.request":
                total += len(msg.get("body", b""))
                if total > limite:
                    # HTTPException passa limpa pelo FastAPI (outra exceção viraria 400).
                    raise HTTPException(413, "Requisição grande demais.")
            return msg

        await self.app(escopo, receber_limitado, enviar_com_cabecalhos)

    async def _registrar_excesso(self, decisao) -> None:  # type: ignore[no-untyped-def]
        """Uma linha de auditoria por regra a cada janela (senão um ataque enche a trilha)."""
        seg = self.seg
        chave_aviso = f"aviso:{decisao.chave}"
        if seg.contadores.quantos(chave_aviso, 300) > 0 and not decisao.novo_bloqueio:
            return
        seg.contadores.adicionar(chave_aviso)
        await anyio.to_thread.run_sync(
            lambda: seg.auditar(
                "antifraude.limite_taxa_excedido",
                depois={"regra": decisao.regra, "bloqueio_novo": decisao.novo_bloqueio},
            )
        )
