"""Simula o parceiro de pagamento confirmando um pagamento na pilha LOCAL.

Uso: python harness/confirmar-pagamento-local.py <pedido_id> <cobranca_id> <valor_centavos> [--porta 8000]

Usa o provedor FAKE do próprio backend (segredo de teste público, só vale para a pilha local):
gera o evento `payment_intent.succeeded` assinado e manda ao webhook de verdade. O `cobranca_id`
aparece no app como "pix-copia-e-cola-fake-<cobranca_id>". Nada de Stripe real.
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "backend" / "src"))

from trato.pagamentos.provedor.fake import SEGREDO_DE_TESTE  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("pedido_id")
    ap.add_argument("cobranca_id")
    ap.add_argument("valor_centavos", type=int)
    ap.add_argument("--porta", type=int, default=8000)
    args = ap.parse_args()

    agora = int(time.time())
    evento = {
        "id": f"evt_local_{agora}_{args.valor_centavos}",
        "type": "payment_intent.succeeded",
        "data": {"object": {
            "id": args.cobranca_id,
            "amount": args.valor_centavos,
            "amount_received": args.valor_centavos,
            "metadata": {"pedido_id": args.pedido_id},
        }},
    }
    corpo = json.dumps(evento).encode()
    assinatura = hmac.new(SEGREDO_DE_TESTE.encode(), f"{agora}.".encode() + corpo, hashlib.sha256).hexdigest()
    cabecalhos = {"Content-Type": "application/json", "Stripe-Signature": f"t={agora},v1={assinatura}"}
    req = urllib.request.Request(
        f"http://127.0.0.1:{args.porta}/v1/webhooks/stripe", data=corpo, method="POST", headers=cabecalhos
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:  # noqa: S310 (localhost)
            print(r.status, r.read().decode())
    except urllib.error.HTTPError as e:
        print(e.code, e.read().decode())


if __name__ == "__main__":
    main()
