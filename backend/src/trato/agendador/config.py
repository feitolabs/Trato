"""Configuração do agendador (.env, prefixo TRATO_AGENDADOR_). Nada fixo no código além do nome."""

from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO


class ConfigAgendador(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        env_prefix="TRATO_AGENDADOR_",
        extra="ignore",
    )

    intervalo_segundos: float = 60.0
    # Pedidos concluídos há até N dias ainda são vigiados (podem ter saldo a liberar).
    dias_concluidos_monitorados: int = 60
    # 0 = sem lembrete de agendamento; N = avisa quando faltam N horas para a janela do serviço.
    lembrete_agenda_horas: int = 0


@lru_cache
def obter_config_agendador() -> ConfigAgendador:
    return ConfigAgendador()
