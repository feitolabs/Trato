"""Garantia: começa na conclusão do serviço; `dias` é congelado ao abrir."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from trato.garantias.config import ConfigGarantia


class ErroGarantia(ValueError):
    pass


def _exigir_aware(momento: datetime) -> None:
    if momento.tzinfo is None:
        raise ErroGarantia("data/hora precisa ter fuso horário")


@dataclass(frozen=True)
class Garantia:
    inicio_em: datetime
    dias: int  # congelado: mudar a config depois não altera garantias existentes

    @property
    def fim_em(self) -> datetime:
        return self.inicio_em + timedelta(days=self.dias)


def abrir_garantia(
    concluido_em: datetime, categoria: str | None, config: ConfigGarantia
) -> Garantia:
    _exigir_aware(concluido_em)
    return Garantia(inicio_em=concluido_em, dias=config.dias_da_categoria(categoria))


def garantia_ativa_agora(garantia: Garantia, agora: datetime) -> bool:
    """Ativa de `inicio_em` até `fim_em`, inclusive. Um segundo depois, expirou."""
    _exigir_aware(agora)
    return garantia.inicio_em <= agora <= garantia.fim_em
