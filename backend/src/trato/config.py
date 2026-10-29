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

    supabase_url: str = ""
    supabase_anon_key: SecretStr = SecretStr("")
    supabase_service_role_key: SecretStr = SecretStr("")
    supabase_db_url: SecretStr = SecretStr("")

    # Persistência real. A URL de conexão ao Postgres do Supabase fica só no .env do João.
    database_url: SecretStr = SecretStr("")
    # Papel usado em cada transação (`set local role`); vazio = o usuário da própria URL.
    trato_banco_papel: str = "service_role"
    # Validação do JWT do Supabase Auth: o segredo HS256 OU a URL das chaves públicas (JWKS).
    supabase_jwt_secret: SecretStr = SecretStr("")
    supabase_jwks_url: str = ""
    # Segredo do servidor para os códigos de check-in/check-out (nunca vai ao banco em claro).
    trato_codigo_segredo: SecretStr = SecretStr("")

    stripe_secret_key: SecretStr = SecretStr("")
    stripe_publishable_key: str = ""
    stripe_webhook_secret: SecretStr = SecretStr("")

    backend_host: str = "127.0.0.1"
    backend_port: int = 8000

    @property
    def stripe_em_modo_teste(self) -> bool:
        return not self.stripe_secret_key.get_secret_value().startswith("sk_live_")


@lru_cache
def obter_config() -> Config:
    return Config()
