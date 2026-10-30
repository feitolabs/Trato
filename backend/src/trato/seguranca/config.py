"""Limites e opções de segurança, lidos do .env (prefixo `TRATO_SEG_`). Nada de limite fixo no
código: os valores abaixo são só o padrão inicial e qualquer um pode ser trocado no .env.

Listas e dicionários entram como JSON, por exemplo:
  TRATO_SEG_CORS_ORIGENS='["https://painel.exemplo.com.br"]'
  TRATO_SEG_LIMITES='[{"nome":"geral","prefixo":"/","escopo":"ip","maximo":200,"janela_s":60}]'
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import BaseModel, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO


class RegraLimite(BaseModel):
    """Uma regra de limite de taxa. Vale para toda rota que começa com `prefixo`."""

    nome: str
    prefixo: str = "/"
    metodos: list[str] = Field(default_factory=list)  # vazio = todos
    escopo: Literal["ip", "usuario"] = "ip"
    maximo: int = Field(gt=0)
    janela_s: int = Field(gt=0)
    bloqueio_s: int = Field(default=0, ge=0)  # bloqueio temporário ao estourar


class RegraUpload(BaseModel):
    tipos: list[str]
    tamanho_max_bytes: int = Field(gt=0)


def _limites_padrao() -> list[RegraLimite]:
    return [
        RegraLimite(nome="geral_ip", escopo="ip", maximo=300, janela_s=60),
        RegraLimite(nome="geral_usuario", escopo="usuario", maximo=120, janela_s=60),
        RegraLimite(
            nome="mensagens",
            prefixo="/v1/pedidos",
            metodos=["POST"],
            escopo="usuario",
            maximo=60,
            janela_s=60,
        ),  # fmt: skip
        RegraLimite(
            nome="lgpd_exportar",
            prefixo="/v1/me/dados",
            escopo="usuario",
            maximo=5,
            janela_s=3600,
            bloqueio_s=3600,
        ),  # fmt: skip
        RegraLimite(
            nome="lgpd_exclusao",
            prefixo="/v1/me/exclusao",
            escopo="usuario",
            maximo=5,
            janela_s=3600,
            bloqueio_s=3600,
        ),  # fmt: skip
        RegraLimite(
            nome="sms",
            prefixo="/v1/seguranca/sms",
            escopo="ip",
            maximo=30,
            janela_s=60,
            bloqueio_s=600,
        ),  # fmt: skip
        RegraLimite(nome="webhooks", prefixo="/v1/webhooks", escopo="ip", maximo=600, janela_s=60),
    ]


def _uploads_padrao() -> dict[str, RegraUpload]:
    imagens = ["image/jpeg", "image/png", "image/webp"]
    return {
        "foto": RegraUpload(tipos=imagens, tamanho_max_bytes=5 * 1024 * 1024),
        "documento": RegraUpload(
            tipos=[*imagens, "application/pdf"], tamanho_max_bytes=10 * 1024 * 1024
        ),
        "anexo_pedido": RegraUpload(
            tipos=[*imagens, "application/pdf", "video/mp4"], tamanho_max_bytes=25 * 1024 * 1024
        ),
    }


class ConfigSeguranca(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="TRATO_SEG_",
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- HTTP ---------------------------------------------------------------------------
    cors_origens: list[str] = Field(default_factory=list)  # vazio = CORS desligado
    cors_metodos: list[str] = Field(
        default_factory=lambda: ["GET", "POST", "PUT", "PATCH", "DELETE"]
    )
    cors_cabecalhos: list[str] = Field(
        default_factory=lambda: [
            "Authorization",
            "Content-Type",
            "Idempotency-Key",
            "X-Dispositivo-Id",
        ]
    )
    corpo_max_bytes: int = Field(default=1_048_576, gt=0)
    corpo_max_por_prefixo: dict[str, int] = Field(default_factory=dict)
    # Só ligar atrás de proxy de confiança (senão o IP vira o que o cliente quiser).
    confiar_x_forwarded_for: bool = False
    hsts_max_age_s: int = Field(default=31_536_000, ge=0)

    # --- Limite de taxa -----------------------------------------------------------------
    limite_taxa_ativo: bool = True
    limites: list[RegraLimite] = Field(default_factory=_limites_padrao)

    # --- SMS pumping (D14: SMS só na confirmação do celular) ----------------------------
    sms_ddis_permitidos: list[str] = Field(default_factory=lambda: ["55"])
    sms_max_por_numero_hora: int = Field(default=3, gt=0)
    sms_max_por_numero_dia: int = Field(default=5, gt=0)
    sms_max_por_dispositivo_dia: int = Field(default=5, gt=0)
    sms_max_numeros_por_dispositivo_dia: int = Field(default=3, gt=0)
    sms_max_por_ip_hora: int = Field(default=10, gt=0)
    sms_faixa_digitos: int = Field(default=9, gt=0)  # prefixo do E.164 que define a "faixa"
    sms_max_por_faixa_hora: int = Field(default=15, gt=0)
    sms_backoff_base_s: int = Field(default=30, ge=0)
    sms_backoff_fator: float = Field(default=2.0, ge=1.0)
    sms_backoff_teto_s: int = Field(default=900, ge=0)
    sms_bloqueio_s: int = Field(default=3600, ge=0)
    # Segredo que o Send SMS Hook manda no cabeçalho. Vazio = rota desligada (503).
    sms_hook_segredo: SecretStr = SecretStr("")

    # --- Conta duplicada e contorno da plataforma ---------------------------------------
    pimenta_identificadores: SecretStr = SecretStr("")  # tempero do hash de CPF/telefone/aparelho
    max_contas_por_dispositivo: int = Field(default=2, gt=0)
    contorno_limiar: int = Field(default=3, gt=0)

    # --- Mascaramento do chat -----------------------------------------------------------
    mascara_min_digitos: int = Field(default=8, gt=0)
    mascara_min_digitos_com_canal: int = Field(default=6, gt=0)  # perto de "zap", "fone"...
    mascara_tlds: list[str] = Field(
        default_factory=lambda: [
            "com", "net", "org", "br", "app", "io", "me", "ly", "co", "link", "bio", "gg", "tv",
            "xyz", "info", "biz", "site", "online", "shop", "store",
        ]
    )  # fmt: skip

    # --- Upload -------------------------------------------------------------------------
    uploads: dict[str, RegraUpload] = Field(default_factory=_uploads_padrao)

    @field_validator("cors_origens")
    @classmethod
    def _sem_curinga(cls, origens: list[str]) -> list[str]:
        if any(o.strip() in ("*", "null") for o in origens):
            raise ValueError("CORS restrito: liste as origens; '*' e 'null' não são aceitos.")
        return [o.rstrip("/") for o in origens]


@lru_cache
def obter_config_seguranca() -> ConfigSeguranca:
    return ConfigSeguranca()
