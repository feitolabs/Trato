"""Cálculo de prazos. Todo horário é timezone-aware; o relógio é injetado pelo chamador."""

from __future__ import annotations

from collections.abc import Collection
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from trato.disputas.config import ConfigDisputa


def _exigir_aware(momento: datetime) -> None:
    if momento.tzinfo is None:
        raise ValueError("datetime precisa ter fuso horário")


def eh_dia_util(dia: date, feriados: Collection[date]) -> bool:
    """Segunda a sexta que não seja feriado."""
    return dia.weekday() < 5 and dia not in feriados


def adicionar_dias_uteis(inicio: datetime, dias: int, feriados: Collection[date] = ()) -> datetime:
    """Soma `dias` úteis mantendo a hora do dia.

    O dia de `inicio` não conta. Cada dia útil seguinte conta 1; sábado, domingo e
    feriados são pulados. Com `dias == 0` devolve `inicio` sem mudança.
    """
    _exigir_aware(inicio)
    if dias < 0:
        raise ValueError("dias deve ser >= 0")
    atual = inicio
    restante = dias
    while restante > 0:
        atual += timedelta(days=1)
        if eh_dia_util(atual.date(), feriados):
            restante -= 1
    return atual


@dataclass(frozen=True)
class Prazos:
    resposta_ate: datetime  # profissional responde até aqui
    decisao_ate: datetime  # analista decide até aqui (conta a partir da abertura)


def calcular_prazos(aberta_em: datetime, config: ConfigDisputa) -> Prazos:
    """Prazos de uma disputa aberta em `aberta_em`.

    Resposta: abertura + horas corridas. Decisão: abertura + dias úteis.
    """
    _exigir_aware(aberta_em)
    return Prazos(
        resposta_ate=aberta_em + timedelta(hours=config.prazo_resposta_horas),
        decisao_ate=adicionar_dias_uteis(
            aberta_em, config.prazo_decisao_dias_uteis, config.feriados
        ),
    )


def dentro_da_janela(concluido_em: datetime, agora: datetime, config: ConfigDisputa) -> bool:
    """O repasse ainda está na janela que o congela? (conclusão + prazo_congelar_repasse_horas,
    limite inclusivo). Só decide o congelamento do repasse; NÃO decide se o cliente pode
    reclamar (ver `prazos_legais.py`)."""
    _exigir_aware(concluido_em)
    _exigir_aware(agora)
    limite = concluido_em + timedelta(hours=config.prazo_congelar_repasse_horas)
    return agora <= limite
