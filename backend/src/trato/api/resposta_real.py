"""Selo de resposta real (ideia #4): só o lado positivo, calculado na leitura (sem coluna).

Para cada pedido em que o profissional enviou orçamento nos últimos `JANELA_DIAS` dias, o tempo é
o primeiro envio dele naquele pedido menos a criação do pedido. Com `MIN_PEDIDOS_RESPONDIDOS` ou
mais e mediana até `MEDIANA_MAXIMA`, vale a faixa; senão é None (nunca uma faixa pior).
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta
from statistics import median
from typing import Any

log = logging.getLogger(__name__)

# Constantes únicas da regra (nenhum número solto nas rotas).
JANELA_DIAS = 90
MIN_PEDIDOS_RESPONDIDOS = 5
MEDIANA_MAXIMA = timedelta(hours=24)
FAIXA_NO_MESMO_DIA = "no mesmo dia"


def responde_em_faixa(contexto: Any, profissional_id: str, agora: datetime) -> str | None:
    """`"no mesmo dia"` ou None. Falha de leitura vira None: o selo é opcional, nunca derruba o
    perfil."""
    try:
        primeiros = contexto.orcamentos.primeiros_envios(
            profissional_id, agora - timedelta(days=JANELA_DIAS)
        )
        tempos: list[float] = []
        for p in primeiros:
            criado = p.pedido_criado_em
            if criado is None:
                pedido = contexto.pedidos.obter(p.pedido_id)
                criado = pedido.aberto_em if pedido is not None else None
            if criado is not None:
                tempos.append(max(0.0, (p.primeiro_envio_em - criado).total_seconds()))
    except Exception:  # noqa: BLE001 - campo opcional
        log.exception("Selo de resposta real falhou")
        return None
    if len(tempos) < MIN_PEDIDOS_RESPONDIDOS:
        return None
    if timedelta(seconds=median(tempos)) <= MEDIANA_MAXIMA:
        return FAIXA_NO_MESMO_DIA
    return None
