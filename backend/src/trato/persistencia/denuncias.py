"""Denúncias no Postgres: insere em `public.alertas_risco` (a fila de risco do painel).

Constraints respeitadas: `severidade` in (baixa, media, alta, critica); `detalhes` não nulo;
índice único `(pedido_id, tipo)` quando há pedido (ver `api/denuncias.py`). O texto somado fica
limitado a `TETO_DETALHES` caracteres.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

import psycopg.errors

from trato.api.denuncias import SEPARADOR, TETO_DETALHES

_NOVO = (
    "insert into public.alertas_risco (usuario_id, pedido_id, tipo, severidade, detalhes, "
    "criado_em) values (%s, %s, %s, %s, left(%s, %s), %s) returning id"
)
_SOMAR = (
    "update public.alertas_risco set detalhes = left(detalhes || %s || %s, %s), "
    "severidade = case when %s = 'alta' and severidade in ('baixa', 'media') "
    "then 'alta' else severidade end "
    "where pedido_id = %s and tipo = %s and not resolvido returning id"
)


class DenunciasPostgres:
    def __init__(self, banco: Any) -> None:
        self._banco = banco

    def registrar(
        self,
        denunciado_id: str,
        pedido_id: str | None,
        tipo: str,
        severidade: str,
        detalhes: str,
        agora: datetime,
    ) -> str:
        with self._banco.transacao() as con:
            try:
                with con.transaction():  # savepoint: a violação não derruba a transação de fora
                    linha = con.execute(
                        _NOVO,
                        (
                            denunciado_id,
                            pedido_id,
                            tipo,
                            severidade,
                            detalhes,
                            TETO_DETALHES,
                            agora,
                        ),
                    ).fetchone()
                return str(linha["id"])
            except psycopg.errors.UniqueViolation:
                pass
            # Já há alerta deste tipo neste pedido: soma ao que ainda está aberto.
            linha = con.execute(
                _SOMAR, (SEPARADOR, detalhes, TETO_DETALHES, severidade, pedido_id, tipo)
            ).fetchone()
            if linha is not None:
                return str(linha["id"])
            # O alerta antigo já foi resolvido: a denúncia nova vira alerta novo, sem o vínculo.
            linha = con.execute(
                _NOVO,
                (
                    denunciado_id,
                    None,
                    tipo,
                    severidade,
                    f"Pedido {pedido_id}: {detalhes}",
                    TETO_DETALHES,
                    agora,
                ),
            ).fetchone()
            return str(linha["id"])

    def contar(self, tipo: str, trecho: str, desde: datetime) -> int:
        with self._banco.transacao() as con:
            linha = con.execute(
                "select count(*) as n from public.alertas_risco "
                "where tipo = %s and criado_em >= %s and position(%s in detalhes) > 0",
                (tipo, desde, trecho),
            ).fetchone()
        return int(linha["n"])
