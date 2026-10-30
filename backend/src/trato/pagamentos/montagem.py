"""Escolha do provedor de pagamento pela configuração (`TRATO_PROVEDOR_PAGAMENTO`).

  fake    (padrão) provedor falso, sem rede nem dinheiro: desenvolvimento e testes.
  stripe  Stripe em MODO TESTE (`sk_test_`); chave `sk_live_` é recusada por `ProvedorStripeTeste`.

Nenhuma chamada real é feita ao escolher; só ao criar cobrança.
"""

from __future__ import annotations

from trato.config import Config, obter_config
from trato.pagamentos.provedor import ErroProvedor, ProvedorFake, ProvedorPagamento
from trato.pagamentos.provedor.stripe_teste import ProvedorStripeTeste, transporte_urllib

PROVEDORES = ("fake", "stripe")


def escolher_provedor(config: Config | None = None) -> ProvedorPagamento:
    config = config or obter_config()
    nome = config.trato_provedor_pagamento.strip().lower()
    if nome == "fake":
        return ProvedorFake()
    if nome == "stripe":
        chave = config.stripe_secret_key.get_secret_value()
        return ProvedorStripeTeste(
            chave, config.stripe_webhook_secret.get_secret_value(), transporte_urllib(chave)
        )
    raise ErroProvedor(f"TRATO_PROVEDOR_PAGAMENTO inválido: {nome!r} (use fake ou stripe).")
