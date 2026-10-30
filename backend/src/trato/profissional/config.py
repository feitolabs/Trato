"""Configuração do cadastro e da verificação do profissional (`TRATO_PRO_*` no .env).

Listas e dicionários entram como JSON, por exemplo:
  TRATO_PRO_VERIFICACAO_NIVEL_POR_CATEGORIA='{"eletricista":"verificado_plus"}'
Os valores abaixo são o padrão inicial (provisório, a confirmar com o João e o jurídico).
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from trato.config import RAIZ_PROJETO

# Do menos para o mais exigente.
ORDEM_NIVEIS = ("verificado", "verificado_plus")


def _documentos_padrao() -> dict[str, list[str]]:
    return {
        "verificado": ["documento_frente", "selfie"],
        "verificado_plus": ["documento_frente", "selfie", "antecedentes"],
    }


class ConfigProfissional(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="TRATO_PRO_",
        env_file=RAIZ_PROJETO / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # --- Cadastro -----------------------------------------------------------------------
    bio_max_chars: int = Field(default=600, gt=0)
    categorias_max: int = Field(default=10, gt=0)
    regioes_max: int = Field(default=30, gt=0)
    portfolio_max: int = Field(default=12, gt=0)
    disponibilidade_max: int = Field(default=21, gt=0)

    # --- Verificação (LGPD: biometria/documento é dado sensível) -------------------------
    verificacao_finalidade: str = (
        "Confirmar que você é quem diz ser e que pode prestar serviços pelo Trato. "
        "Os documentos só são vistos pela equipe de cadastro e não são compartilhados."
    )
    # Quanto tempo os documentos ficam guardados depois do envio (N10: prazo a confirmar).
    verificacao_retencao_dias: int = Field(default=365, gt=0)
    # Nível mínimo proporcional ao risco: chave = slug ou id da categoria.
    verificacao_nivel_padrao: str = "verificado"
    verificacao_nivel_por_categoria: dict[str, str] = Field(default_factory=dict)
    verificacao_documentos_obrigatorios: dict[str, list[str]] = Field(
        default_factory=_documentos_padrao
    )

    def nivel_exigido(self, chaves_categorias: list[str]) -> str:
        """O mais exigente entre o padrão e o das categorias do profissional."""
        niveis = [self.verificacao_nivel_padrao]
        niveis += [self.verificacao_nivel_por_categoria.get(c, "") for c in chaves_categorias]
        validos = [n for n in niveis if n in ORDEM_NIVEIS]
        return max(validos, key=ORDEM_NIVEIS.index) if validos else ORDEM_NIVEIS[0]


@lru_cache
def obter_config_profissional() -> ConfigProfissional:
    return ConfigProfissional()
