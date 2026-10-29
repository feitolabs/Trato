"""Configuração dos prazos. Os valores vêm da tabela de configuração, nunca do código."""

from __future__ import annotations

from collections.abc import Collection, Mapping
from dataclasses import dataclass, field
from datetime import date
from types import MappingProxyType


@dataclass(frozen=True)
class ConfigDisputa:
    """Sem valores padrão de propósito: quem chama busca na tabela de configuração.

    prazo_resposta_horas: prazo do profissional para responder (escopo: 48 h).
    prazo_decisao_dias_uteis: prazo do analista para decidir (escopo: 5 dias úteis).
    prazo_congelar_repasse_horas: janela após a conclusão em que o repasse fica retido
        (escopo: 72 h). É regra comercial NOSSA e configurável; não limita o direito de
        reclamar (P1 define se são 48 h, 72 h ou 7 dias).
    prazos_legais: prazos da lei para reclamar (CDC etc.), só INFORMATIVOS. Quem define os
        números é o advogado (docs/advogado-e-contador.md); vazio = nada informado.
    feriados: datas que não contam como dia útil.
    """

    prazo_resposta_horas: int
    prazo_decisao_dias_uteis: int
    prazo_congelar_repasse_horas: int
    feriados: Collection[date] = field(default_factory=frozenset)
    prazos_legais: Mapping[str, int] = field(default_factory=dict)  # nome -> dias

    def __post_init__(self) -> None:
        for nome in (
            "prazo_resposta_horas",
            "prazo_decisao_dias_uteis",
            "prazo_congelar_repasse_horas",
        ):
            valor = getattr(self, nome)
            if isinstance(valor, bool) or not isinstance(valor, int) or valor < 0:
                raise ValueError(f"{nome} deve ser inteiro >= 0")
        object.__setattr__(self, "feriados", frozenset(self.feriados))
        for dias in self.prazos_legais.values():
            if isinstance(dias, bool) or not isinstance(dias, int) or dias <= 0:
                raise ValueError("prazos_legais deve ter dias inteiros > 0")
        object.__setattr__(self, "prazos_legais", MappingProxyType(dict(self.prazos_legais)))
