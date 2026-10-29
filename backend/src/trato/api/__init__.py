"""Camada HTTP (FastAPI) sobre as regras puras. Só orquestra: não calcula dinheiro.

Dependências (auth, repositórios, configuração, relógio) entram por `Contexto`, então os
adaptadores do Supabase/Stripe podem ser ligados depois sem mexer nas rotas.
"""

from trato.api.app import criar_app, instalar
from trato.api.contexto import Contexto

__all__ = ["Contexto", "criar_app", "instalar"]
