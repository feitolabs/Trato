"""Prazos de garantia e retrabalho. Vêm da tabela de configuração, nunca fixos no fluxo."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from types import MappingProxyType

# Garantia mínima legal (CDC, art. 26): serviço DURÁVEL 90 dias, NÃO DURÁVEL 30 dias.
# Chave = slug da categoria. Slug fora dos dois conjuntos vale o piso de 30 dias.
GARANTIA_MINIMA_DURAVEL_DIAS = 90
GARANTIA_MINIMA_NAO_DURAVEL_DIAS = 30
SLUGS_DURAVEIS = frozenset(
    {
        "ar-condicionado",
        "cameras-seguranca",
        "chaveiro",
        "cortinas-persianas",
        "eletricista",
        "eletrodomesticos",
        "encanador",
        "gesso-drywall",
        "impermeabilizacao",
        "informatica-redes",
        "marcenaria",
        "montagem-de-moveis",
        "pintura-interna",
        "pisos-revestimentos",
        "reparos-gerais",
        "serralheria",
        "vidraceiro",
    }
)
SLUGS_NAO_DURAVEIS = frozenset(
    {"diarista", "jardinagem", "limpeza-especial", "limpeza-residencial", "mudanca-frete"}
)


def garantia_minima_do_slug(slug: str | None) -> int:
    """Dias mínimos de garantia da categoria (pelo slug)."""
    if slug in SLUGS_DURAVEIS:
        return GARANTIA_MINIMA_DURAVEL_DIAS
    return GARANTIA_MINIMA_NAO_DURAVEL_DIAS


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
    # Piso legal por categoria (chave = id): a garantia aberta nunca fica abaixo dele.
    minimo_dias_por_categoria: Mapping[str, int] = field(
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
        object.__setattr__(
            self,
            "minimo_dias_por_categoria",
            MappingProxyType(dict(self.minimo_dias_por_categoria)),
        )

    def minimo_da_categoria(self, categoria: str | None) -> int:
        if categoria is None:
            return 0
        return self.minimo_dias_por_categoria.get(categoria, 0)

    def dias_da_categoria(self, categoria: str | None) -> int:
        if categoria is None:
            return self.garantia_dias_padrao
        return self.garantia_dias_por_categoria.get(categoria, self.garantia_dias_padrao)
