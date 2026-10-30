"""Webhook do Stripe: assinatura inválida, ausente, antiga, válida e reenvio.

Fala com o backend em TRATO_API_URL (padrão http://127.0.0.1:8000). NÃO chama o Stripe e NÃO cria
conta. As verificações de recusa não gravam nada. As de aceite (assinatura válida e reenvio)
enviam UM evento de tipo desconhecido (`trato.teste_ping`, sem efeito no pedido nem no dinheiro).
`eventos_webhook` é imutável por desenho (não dá para apagar a linha), por isso:
  * contra backend em MEMÓRIA (TRATO_PERSISTENCIA=memoria) não sobra nada: é o modo recomendado;
  * contra backend com banco real, só rode com TRATO_PERMITE_EVENTO_NO_BANCO=sim (fica 1 linha evt_teste_*).
Variáveis: TRATO_TESTE_REAL=sim, STRIPE_WEBHOOK_SECRET (o whsec_ do modo teste), TRATO_API_URL.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import secrets
import time

from teste_real_comum import encerrar, exigir_teste_real, http, json_de, registra, variavel

exigir_teste_real()
SEGREDO = variavel("STRIPE_WEBHOOK_SECRET")
API = (variavel("TRATO_API_URL", False) or "http://127.0.0.1:8000").rstrip("/")
ROTA = f"{API}/v1/webhooks/stripe"
GRAVA_NO_BANCO = os.environ.get("TRATO_PERMITE_EVENTO_NO_BANCO") == "sim"
MEMORIA = os.environ.get("TRATO_PERSISTENCIA", "memoria") == "memoria"


def assinar(corpo: bytes, segredo: str, t: int | None = None) -> str:
    t = int(time.time()) if t is None else t
    mac = hmac.new(segredo.encode(), f"{t}.".encode() + corpo, hashlib.sha256).hexdigest()
    return f"t={t},v1={mac}"


def enviar(corpo: bytes, assinatura: str | None) -> tuple[int, object]:
    cab = {"Content-Type": "application/json"}
    if assinatura:
        cab["Stripe-Signature"] = assinatura
    status, resposta = http("POST", ROTA, cab, corpo)
    return status, json_de(resposta)


evento_id = f"evt_teste_{secrets.token_hex(8)}"
corpo = json.dumps({"id": evento_id, "type": "trato.teste_ping", "data": {"object": {}}}).encode()

status, _ = enviar(corpo, None)
registra("sem cabeçalho Stripe-Signature → 400", status == 400, f"status={status}")
status, _ = enviar(corpo, assinar(corpo, "whsec_segredo_errado_" + secrets.token_hex(4)))
registra("assinatura de outro segredo → 400", status == 400, f"status={status}")
status, _ = enviar(corpo, assinar(corpo + b" ", SEGREDO))
registra("corpo alterado depois de assinado → 400", status == 400, f"status={status}")
status, _ = enviar(corpo, assinar(corpo, SEGREDO, t=int(time.time()) - 3600))
registra("assinatura válida mas de 1 hora atrás (fora da tolerância) → 400", status == 400, f"status={status}")

if MEMORIA or GRAVA_NO_BANCO:
    status, dados = enviar(corpo, assinar(corpo, SEGREDO))
    registra(
        "assinatura válida → 200, recebido, não duplicado",
        status == 200 and isinstance(dados, dict) and dados.get("recebido") is True
        and dados.get("duplicado") is False,
        f"status={status} corpo={dados}",
    )
    status, dados = enviar(corpo, assinar(corpo, SEGREDO))
    registra(
        "reenvio do mesmo evento → 200 e duplicado=true (o efeito não se repete)",
        status == 200 and isinstance(dados, dict) and dados.get("duplicado") is True,
        f"status={status} corpo={dados}",
    )
else:
    registra(
        "assinatura válida e reenvio",
        None,
        "backend com banco real: defina TRATO_PERMITE_EVENTO_NO_BANCO=sim (deixa 1 linha evt_teste_*)",
    )
encerrar()
