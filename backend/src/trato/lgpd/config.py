"""Prazos e opções de LGPD, lidos do .env (prefixo `TRATO_LGPD_`).

ATENÇÃO: os prazos de retenção abaixo são PROPOSTA para o jurídico/contador validar (ver
`docs/advogado-e-contador.md`, N10). Nada é apagado por prazo automático enquanto o João/DPO não
confirmar. Trocar no .env, por exemplo:
  TRATO_LGPD_RETENCAO_DIAS='{"ledger_financeiro":1825,"logs_acesso":180}'
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO


class Finalidade(BaseModel):
    obrigatoria: bool = False  # não dá para revogar sem encerrar a conta


def _retencao_padrao() -> dict[str, int]:
    return {
        "ledger_financeiro": 1825,  # fiscal/contábil (proposta: 5 anos)
        "auditoria": 1825,
        "contratos_e_pedidos": 1825,  # defesa em processo (proposta)
        "mensagens_e_disputas": 1825,
        "logs_acesso": 180,  # Marco Civil, art. 15 (6 meses) — confirmar com o jurídico
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
    finalidades: dict[str, Finalidade] = Field(default_factory=_finalidades_padrao)


@lru_cache
def obter_config_lgpd() -> ConfigLgpd:
    return ConfigLgpd()
