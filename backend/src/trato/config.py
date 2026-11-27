"""Configuração lida do .env (raiz do projeto). Nenhum segredo fica no código."""

from functools import lru_cache
from pathlib import Path

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

RAIZ_PROJETO = Path(__file__).resolve().parents[3]


class Config(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    trato_ambiente: str = "desenvolvimento"
    # memoria (padrão, para testes rápidos) | postgres (Supabase)
    trato_persistencia: str = "memoria"
    # E-mail do atendimento ao usuário (aparece na Central de ajuda). Vazio = o botão não aparece.
    trato_suporte_email: str = ""
    # true = o próprio processo da API roda o agendador (liberação por prazo, expiração de pedido
    # e de pagamento, lembretes). Vários processos juntos são seguros: o agendador usa trava no
    # banco. false = rode `python -m trato.agendador` à parte.
    trato_agendador_embutido: bool = False

    supabase_url: str = ""
    supabase_anon_key: SecretStr = SecretStr("")
    supabase_service_role_key: SecretStr = SecretStr("")
    supabase_db_url: SecretStr = SecretStr("")

    # Persistência real. A URL de conexão ao Postgres do Supabase fica só no .env do João.
    database_url: SecretStr = SecretStr("")
    # Papel usado em cada transação (`set local role`); vazio = o usuário da própria URL.
    trato_banco_papel: str = "service_role"
    # Pool de conexões do processo (UM só `Banco`, dividido entre a API e o agendador embutido).
    # O pooler do Supabase em modo sessão (5432) aceita 15 clientes no total: com 2 máquinas e
    # deploy rolling, cada processo precisa de poucas (max 3 + 1 da trava do agendador).
    trato_banco_pool_min: int = 1
    trato_banco_pool_max: int = 3
    # Validação do JWT do Supabase Auth: o segredo HS256 OU a URL das chaves públicas (JWKS).
    supabase_jwt_secret: SecretStr = SecretStr("")
    supabase_jwks_url: str = ""
    # Segredo do servidor para os códigos de check-in/check-out (nunca vai ao banco em claro).
    trato_codigo_segredo: SecretStr = SecretStr("")
    # Pepper (segredo) para HMAC-SHA256 de impedimento de cadastro (Termos 20.9).
    conta_impedimento_pepper: SecretStr = SecretStr("")

    # fake (padrão) | stripe (modo teste). Ver `trato.pagamentos.montagem`.
    trato_provedor_pagamento: str = "fake"
    stripe_secret_key: SecretStr = SecretStr("")
    stripe_publishable_key: str = ""
    stripe_webhook_secret: SecretStr = SecretStr("")
    # Liga o Pix no app (`pix_disponivel`). Só vira true depois que o Pix estiver ativo no painel do
    # Stripe. Fly/env: TRATO_PIX_HABILITADO=true. Padrão: desligado.
    trato_pix_habilitado: bool = False

    backend_host: str = "127.0.0.1"
    backend_port: int = 8000

    @property
    def stripe_em_modo_teste(self) -> bool:
        return not self.stripe_secret_key.get_secret_value().startswith("sk_live_")


@lru_cache
def obter_config() -> Config:
    return Config()
