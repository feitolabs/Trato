"""Configuração dos prazos. Os valores vêm da tabela de configuração, nunca do código."""

from __future__ import annotations

from collections.abc import Collection
from dataclasses import dataclass, field
from datetime import date


@dataclass(frozen=True)
class ConfigDisputa:
    """Sem valores padrão de propósito: quem chama busca na tabela de configuração.

    prazo_resposta_horas: prazo do profissional para responder (escopo: 48 h).
    prazo_decisao_dias_uteis: prazo do analista para decidir (escopo: 5 dias úteis).
    prazo_congelar_repasse_horas: janela após a conclusão em que o repasse fica retido
        e o cliente ainda pode abrir disputa (escopo: 72 h).
    feriados: datas que não contam como dia útil.
    """

    prazo_resposta_horas: int
    prazo_decisao_dias_uteis: int
    prazo_congelar_repasse_horas: int
    feriados: Collection[date] = field(default_factory=frozenset)

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
