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

    supabase_url: str = ""
    supabase_anon_key: SecretStr = SecretStr("")
    supabase_service_role_key: SecretStr = SecretStr("")
    supabase_db_url: SecretStr = SecretStr("")

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
