"""Configuração de upload (`TRATO_UP_*` no .env). Nada fixo no código."""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO


class ConfigUploads(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="TRATO_UP_",
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # URL de envio assinada: curta de propósito.
    url_envio_segundos: int = Field(default=300, gt=0)
    # Depois disso a solicitação não pode mais ser concluída.
    solicitacao_validade_segundos: int = Field(default=3600, gt=0)
    # Check-in: distância máxima entre o aparelho e o local do pedido (calculada no servidor).
    checkin_distancia_max_m: int = Field(default=500, gt=0)


@lru_cache
def obter_config_uploads() -> ConfigUploads:
    return ConfigUploads()
