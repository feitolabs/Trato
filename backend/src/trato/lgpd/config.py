"""Prazos e opções de LGPD, lidos do .env (prefixo `TRATO_LGPD_`).

ATENÇÃO: os prazos de retenção abaixo são PROPOSTA para o jurídico/contador validar (ver
`docs/advogado-e-contador.md`, N10). Nada é apagado por prazo automático enquanto o João/DPO não
confirmar. Trocar no .env, por exemplo:
  TRATO_LGPD_RETENCAO_DIAS='{"ledger_financeiro":1825,"logs_acesso":365}'
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO

# Termos 14.8 / Marco Civil, art. 15: registros de acesso por no mínimo 6 meses.
MINIMO_LOGS_ACESSO_DIAS = 184


class Finalidade(BaseModel):
    obrigatoria: bool = False  # não dá para revogar sem encerrar a conta


def _retencao_padrao() -> dict[str, int]:
    return {
        "ledger_financeiro": 1825,  # fiscal/contábil (proposta: 5 anos)
        "auditoria": 1825,
        "contratos_e_pedidos": 1825,  # defesa em processo (proposta)
        "mensagens_e_disputas": 1825,
        "logs_acesso": MINIMO_LOGS_ACESSO_DIAS,  # piso legal: valor menor é elevado
        "documentos_verificacao": 90,  # proposta; pendente N10
    }


def _finalidades_padrao() -> dict[str, Finalidade]:
    return {
        "termos_de_uso": Finalidade(obrigatoria=True),
        "politica_privacidade": Finalidade(obrigatoria=True),
        "verificacao_identidade": Finalidade(),
        "biometria_facial": Finalidade(),
        "localizacao_no_servico": Finalidade(),
        "comunicacoes_marketing": Finalidade(),
    }


class ConfigLgpd(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="TRATO_LGPD_",
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    retencao_dias: dict[str, int] = Field(default_factory=_retencao_padrao)
    # Tempo para o titular desistir antes de a anonimização rodar.
    carencia_exclusao_dias: int = Field(default=7, ge=0)
    confirmacao_validade_min: int = Field(default=30, gt=0)
    # Termos 13.10 e I.11: encerrada pelo Trato sem falta, os Tratinhos ficam guardados (o
    # prazo pode ser maior que o dos Termos, nunca menor).
    tratinhos_guarda_encerramento_dias: int = Field(default=90, ge=90)
    finalidades: dict[str, Finalidade] = Field(default_factory=_finalidades_padrao)

    @field_validator("retencao_dias")
    @classmethod
    def _piso_dos_registros_de_acesso(cls, valor: dict[str, int]) -> dict[str, int]:
        atual = valor.get("logs_acesso", MINIMO_LOGS_ACESSO_DIAS)
        return {**valor, "logs_acesso": max(atual, MINIMO_LOGS_ACESSO_DIAS)}


@lru_cache
def obter_config_lgpd() -> ConfigLgpd:
    return ConfigLgpd()
