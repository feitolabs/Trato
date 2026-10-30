"""Prazos de garantia e retrabalho. Vêm da tabela de configuração, nunca fixos no fluxo."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from types import MappingProxyType


@dataclass(frozen=True)
class ConfigGarantia:
    """Padrão + sobrescrita por categoria (chave = id/slug da categoria).

    Os números abaixo são só o padrão do escopo 3.6; em produção o valor
    carregado da configuração versionada substitui estes.
    """

    garantia_dias_padrao: int = 30
    prazo_atendimento_dias: int = 7
    # D13: garantia financiada pelo Trato está fora do MVP. Liga só por configuração
    # (tabela), depois da definição de P8 (fundo) e do parecer jurídico. O retrabalho com o
    # mesmo profissional segue como "suporte e análise de problemas".
    garantia_financiada_habilitada: bool = False
    garantia_dias_por_categoria: Mapping[str, int] = field(
        default_factory=lambda: MappingProxyType({})
    )

    def __post_init__(self) -> None:
        if not isinstance(self.garantia_financiada_habilitada, bool):
            raise ValueError("garantia_financiada_habilitada deve ser verdadeiro ou falso")
        if self.garantia_dias_padrao <= 0 or self.prazo_atendimento_dias <= 0:
            raise ValueError("prazos devem ser maiores que zero")
        if any(d <= 0 for d in self.garantia_dias_por_categoria.values()):
            raise ValueError("prazo de categoria deve ser maior que zero")
        object.__setattr__(
            self,
            "garantia_dias_por_categoria",
            MappingProxyType(dict(self.garantia_dias_por_categoria)),
        )

    def dias_da_categoria(self, categoria: str | None) -> int:
        if categoria is None:
            return self.garantia_dias_padrao
        return self.garantia_dias_por_categoria.get(categoria, self.garantia_dias_padrao)
