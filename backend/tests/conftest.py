"""Isola a suíte do ambiente da máquina: o resultado é o mesmo com ou sem `.env` real na raiz.

Sem isto, um `.env` com `TRATO_PERSISTENCIA=postgres`, chave do Stripe e segredos faz os testes em
memória falharem (achado 6 de `docs/teste-real-banco.md`). Roda na importação, antes de qualquer
`Config()` ser criado; os testes que precisam de valores os passam por `Config(...)` ou `monkeypatch`.
"""

from __future__ import annotations

import os

from trato.config import Config, obter_config

Config.model_config["env_file"] = None  # nunca ler o `.env` da raiz nos testes
for _campo in Config.model_fields:
    os.environ.pop(_campo.upper(), None)  # nem variáveis já exportadas no shell
obter_config.cache_clear()
