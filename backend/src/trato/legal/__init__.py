"""Versões publicadas dos Termos de uso, para entregar a cópia da Contratação (cláusula 5.3).

Cada versão publicada fica num arquivo próprio e não muda mais. Versão nova: novo arquivo
`termos-de-uso-<versão>.md` e nova linha em `VERSOES`, com o dia em que passa a valer.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

from trato.financeiro import periodo

_PASTA = Path(__file__).parent


@dataclass(frozen=True)
class VersaoDosTermos:
    versao: str
    vigente_desde: date  # dia em America/Sao_Paulo

    def texto(self) -> str:
        return (_PASTA / f"termos-de-uso-{self.versao}.md").read_text(encoding="utf-8")


# Em ordem de vigência.
VERSOES: tuple[VersaoDosTermos, ...] = (VersaoDosTermos("1.1", date(2026, 11, 22)),)


def vigente_em(instante: datetime) -> VersaoDosTermos | None:
    """Versão em vigor no instante (23.6). None: não temos o texto daquela época."""
    dia = instante.astimezone(periodo.BRASILIA).date()
    return next((v for v in reversed(VERSOES) if v.vigente_desde <= dia), None)
