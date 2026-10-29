"""Prazos legais para reclamar: SÓ INFORMATIVOS (D13).

Diferente da janela que congela o repasse (`prazos.dentro_da_janela`, regra comercial nossa),
estes prazos vêm da lei e dos pareceres do advogado. Aqui eles apenas viram datas para mostrar
ao usuário. Nada neste módulo recusa, encerra ou decide uma reclamação: o direito de reclamar
nunca é renunciado por regra automática.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from trato.disputas.config import ConfigDisputa


@dataclass(frozen=True)
class PrazoLegalInformativo:
    nome: str
    ate: datetime
    informativo: bool = True  # sempre verdadeiro: não bloqueia nada


def prazos_legais_informativos(
    concluido_em: datetime, config: ConfigDisputa
) -> tuple[PrazoLegalInformativo, ...]:
    if concluido_em.tzinfo is None:
        raise ValueError("datetime precisa ter fuso horário")
    return tuple(
        PrazoLegalInformativo(nome, concluido_em + timedelta(days=dias))
        for nome, dias in sorted(config.prazos_legais.items())
    )
