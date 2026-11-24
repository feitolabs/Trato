"""Denúncias no Postgres: insere em `public.alertas_risco` (a fila de risco do painel).

Constraints respeitadas: `severidade` in (baixa, media, alta, critica); `detalhes` não nulo;
índice único `(pedido_id, tipo)` quando há pedido (ver `api/denuncias.py`).
"""

from __future__ import annotations

from typing import Any

import psycopg.errors

_NOVO = (
    "insert into public.alertas_risco (usuario_id, pedido_id, tipo, severidade, detalhes) "
    "values (%s, %s, %s, %s, %s) returning id"
)
_SOMAR = (
    "update public.alertas_risco set detalhes = detalhes || chr(10) || '---' || chr(10) || %s, "
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
    ) -> str:
        with self._banco.transacao() as con:
            try:
                with con.transaction():  # savepoint: a violação não derruba a transação de fora
                    linha = con.execute(
                        _NOVO, (denunciado_id, pedido_id, tipo, severidade, detalhes)
                    ).fetchone()
                return str(linha["id"])
            except psycopg.errors.UniqueViolation:
                pass
            # Já há alerta deste tipo neste pedido: soma ao que ainda está aberto.
            linha = con.execute(_SOMAR, (detalhes, severidade, pedido_id, tipo)).fetchone()
            if linha is not None:
                return str(linha["id"])
            # O alerta antigo já foi resolvido: a denúncia nova vira alerta novo, sem o vínculo.
            linha = con.execute(
                _NOVO, (denunciado_id, None, tipo, severidade, f"Pedido {pedido_id}: {detalhes}")
            ).fetchone()
            return str(linha["id"])
