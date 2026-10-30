"""Configuração de notificações lida do .env (prefixo TRATO_NOTIF_). Nada de segredo no código.

Tudo vem desligado: sem as variáveis, só o canal `app` (a caixa de entrada) funciona. Ligar push,
e-mail ou SMS é só preencher o `.env` (ver docs/backend-notificacoes.md).
"""

from __future__ import annotations

from datetime import timedelta
from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO


class ConfigNotificacoes(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        env_prefix="TRATO_NOTIF_",
        extra="ignore",
    )

    # Base do deep link que o app abre (esquema registrado no app).
    deep_link_base: str = "trato://"
    # Canais ligados por padrão para quem nunca mexeu nas preferências.
    padrao_app: bool = True
    padrao_push: bool = True
    padrao_email: bool = False
    # Reenvio: só tenta de novo notificações mais novas que isto (horas) e no máximo N por ciclo.
    reenvio_janela_horas: int = 24
    reenvio_lote: int = 100

    # Push (FCM para Android/web; APNs direto para iOS é opcional).
    push_ativo: bool = False
    fcm_projeto_id: str = ""
    fcm_credenciais_arquivo: str = ""  # caminho do JSON da conta de serviço (fora do git)
    apns_ativo: bool = False
    apns_chave_arquivo: str = ""  # caminho do .p8 (fora do git)
    apns_chave_id: str = ""
    apns_time_id: str = ""
    apns_bundle_id: str = ""

    # E-mail (SMTP).
    email_ativo: bool = False
    smtp_host: str = ""
    smtp_porta: int = 587
    smtp_usuario: str = ""
    smtp_senha: SecretStr = SecretStr("")
    email_remetente: str = ""

    # SMS: só confirmação de celular (D14). O envio real é do Send SMS Hook do Supabase Auth.
    sms_ativo: bool = False
    sms_provedor_url: str = ""
    sms_provedor_chave: SecretStr = SecretStr("")
    sms_max_envios_por_celular: int = 3

    @property
    def reenvio_janela(self) -> timedelta:
        return timedelta(hours=self.reenvio_janela_horas)


@lru_cache
def obter_config_notificacoes() -> ConfigNotificacoes:
    return ConfigNotificacoes()
