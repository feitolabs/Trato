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
    # Padrão 2 h; TRATO_AGENDADOR_LEMBRETE_AGENDA_HORAS=0 desliga.
    lembrete_agenda_horas: int = 2
    # Só reenvia ordem de estorno criada há pelo menos isto (o envio logo após o commit pode
    # estar em andamento).
    estorno_idade_minima_segundos: int = 120


@lru_cache
def obter_config_agendador() -> ConfigAgendador:
    return ConfigAgendador()
