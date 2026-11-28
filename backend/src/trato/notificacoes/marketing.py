"""Quem pode receber campanha de marketing (LGPD): o ÚLTIMO registro de
`comunicacoes_marketing` precisa ser um aceite E o push de marketing não pode estar desligado.
A estimativa e o disparo usam a mesma função."""

from __future__ import annotations

from collections.abc import Collection, Sequence
from typing import Any, Protocol

FINALIDADE = "comunicacoes_marketing"


class FonteDeConsentimento(Protocol):
    def ultimos(self, usuario_ids: Sequence[str], finalidade: str) -> dict[str, bool]:
        """usuario_id -> `aceito` da última linha (registrado_em, id). Sem linha: fora do mapa."""
        ...


def separar_marketing(
    ids: Sequence[Any], consentimentos: FonteDeConsentimento, desligados: Collection[Any]
) -> tuple[list[Any], int]:
    """(quem recebe, quantos ficam de fora: sem consentimento ou push desligado, sem contar
    ninguém duas vezes). Erro na leitura sobe: quem chama não envia nada."""
    ultimos = consentimentos.ultimos([str(i) for i in ids], FINALIDADE)
    desligou = {str(i) for i in desligados}
    recebem = [i for i in ids if ultimos.get(str(i)) is True and str(i) not in desligou]
    return recebem, len(ids) - len(recebem)
