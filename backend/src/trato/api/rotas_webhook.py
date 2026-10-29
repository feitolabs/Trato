"""Receptor de webhook do Stripe: assinatura, idempotência e despacho por tipo de evento.

Aqui não se decide nada de dinheiro. O que fazer com cada tipo de evento (ledger e transição
do pedido) é ponto de extensão da F4.4: registre um manipulador em
`Contexto.manipuladores_webhook["<tipo>"]`. Tipo sem manipulador é guardado e respondido 200
para o Stripe não reenviar.
"""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Header, HTTPException, Request

from trato.api.contexto import Contexto, obter_contexto
from trato.api.modelos import WebhookOut
from trato.api.repositorios import EventoWebhook
from trato.api.webhook_pagamento import EventoForaDeOrdem
from trato.pagamentos.idempotencia import processar_uma_vez
from trato.pagamentos.webhook import AssinaturaInvalida, verificar_assinatura

router = APIRouter(prefix="/v1/webhooks", tags=["webhooks"])

PROVEDOR = "stripe"


@router.post(
    "/stripe",
    response_model=WebhookOut,
    summary="Webhook do Stripe",
    description=(
        "Não usa login: a autenticidade vem do cabeçalho `Stripe-Signature` (HMAC com o "
        "segredo de `STRIPE_WEBHOOK_SECRET`). Reenvio do mesmo evento é aceito sem repetir "
        "o efeito."
    ),
)
async def receber_stripe(
    request: Request,
    stripe_signature: str | None = Header(None, alias="Stripe-Signature"),
    contexto: Contexto = Depends(obter_contexto),
) -> WebhookOut:
    segredo = contexto.segredo_webhook()
    if not segredo:
        raise HTTPException(503, "Webhook não configurado.")
    corpo = await request.body()
    agora = contexto.agora()
    try:
        verificar_assinatura(corpo, stripe_signature, segredo, agora=int(agora.timestamp()))
    except AssinaturaInvalida as erro:
        raise HTTPException(400, "Assinatura do webhook inválida.") from erro

    try:
        dados = json.loads(corpo)
    except ValueError as erro:
        raise HTTPException(400, "Corpo do webhook não é um JSON válido.") from erro
    evento_id = dados.get("id") if isinstance(dados, dict) else None
    tipo = dados.get("type") if isinstance(dados, dict) else None
    if not isinstance(evento_id, str) or not evento_id or not isinstance(tipo, str):
        raise HTTPException(400, "Evento sem id ou tipo.")

    evento = EventoWebhook(PROVEDOR, evento_id, tipo, dados, agora)
    manipulador = contexto.manipuladores_webhook.get(tipo)

    def processar() -> None:
        if manipulador is not None:
            manipulador(evento, contexto)
        contexto.eventos_webhook.registrar(evento)  # só guarda o que foi tratado sem erro

    try:
        executou, _ = processar_uma_vez(
            contexto.eventos_webhook, f"{PROVEDOR}:{evento_id}", processar
        )
    except EventoForaDeOrdem as erro:
        # A chave volta a ficar livre: o provedor reenvia quando o pedido estiver pronto.
        raise HTTPException(409, "Evento antes do tempo; tente de novo.") from erro
    return WebhookOut(recebido=True, duplicado=not executou, tratado=manipulador is not None)
