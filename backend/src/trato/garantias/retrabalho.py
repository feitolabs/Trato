"""Retrabalho: abertura, estados e vencimento do prazo de atendimento.

Regras definidas aqui:
- Só abre dentro da garantia (fim inclusive).
- Um retrabalho em curso por vez por garantia (aberto, aceito, em_execucao,
  nao_atendido). Depois de resolvido ou reatribuído pode abrir outro, ainda
  dentro da garantia (outro defeito). Sem limite fixo de quantidade.
- `atender_ate` = abertura + prazo de atendimento; o último instante vale,
  um segundo depois vence. Só aberto/aceito vencem (em execução já foi atendido).
- Sem dinheiro aqui: quem paga o outro profissional é a P8 (em aberto).
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from enum import StrEnum
from typing import Any

from trato.garantias.config import ConfigGarantia
from trato.garantias.garantia import Garantia, garantia_ativa_agora


class ErroRetrabalho(ValueError):
    pass


class EstadoRetrabalho(StrEnum):
    ABERTO = "aberto"
    ACEITO = "aceito"
    EM_EXECUCAO = "em_execucao"
    RESOLVIDO = "resolvido"
    NAO_ATENDIDO = "nao_atendido"
    REATRIBUIDO = "reatribuido"


E = EstadoRetrabalho

TRANSICOES: dict[EstadoRetrabalho, frozenset[EstadoRetrabalho]] = {
    E.ABERTO: frozenset({E.ACEITO, E.NAO_ATENDIDO}),
    E.ACEITO: frozenset({E.EM_EXECUCAO, E.NAO_ATENDIDO}),
    E.EM_EXECUCAO: frozenset({E.RESOLVIDO}),
    E.NAO_ATENDIDO: frozenset({E.REATRIBUIDO}),
    E.RESOLVIDO: frozenset(),
    E.REATRIBUIDO: frozenset(),
}

EM_CURSO = frozenset({E.ABERTO, E.ACEITO, E.EM_EXECUCAO, E.NAO_ATENDIDO})
PRAZO_CORRE = frozenset({E.ABERTO, E.ACEITO})


@dataclass(frozen=True)
class Retrabalho:
    aberto_em: datetime
    atender_ate: datetime
    descricao: str
    estado: EstadoRetrabalho = E.ABERTO
    atendido_em: datetime | None = None
    outro_profissional_id: str | None = None


def abrir_retrabalho(
    garantia: Garantia,
    descricao: str,
    agora: datetime,
    config: ConfigGarantia,
    existentes: Iterable[Retrabalho] = (),
) -> Retrabalho:
    if not descricao.strip():
        raise ErroRetrabalho("descreva o defeito")
    if not garantia_ativa_agora(garantia, agora):
        raise ErroRetrabalho("garantia fora do prazo")
    if any(r.estado in EM_CURSO for r in existentes):
        raise ErroRetrabalho("já existe um retrabalho em curso nesta garantia")
    return Retrabalho(
        aberto_em=agora,
        atender_ate=agora + timedelta(days=config.prazo_atendimento_dias),
        descricao=descricao.strip(),
    )


def deve_virar_nao_atendido(retrabalho: Retrabalho, agora: datetime) -> bool:
    """Vencido = `agora` depois de `atender_ate` e ainda aberto/aceito."""
    return retrabalho.estado in PRAZO_CORRE and agora > retrabalho.atender_ate


def transicionar(
    retrabalho: Retrabalho,
    novo: EstadoRetrabalho,
    agora: datetime,
    outro_profissional_id: str | None = None,
) -> Retrabalho:
    if novo not in TRANSICOES[retrabalho.estado]:
        raise ErroRetrabalho(f"transição inválida: {retrabalho.estado} -> {novo}")
    if novo is E.NAO_ATENDIDO and not deve_virar_nao_atendido(retrabalho, agora):
        raise ErroRetrabalho("prazo de atendimento ainda não venceu")
    if novo is E.REATRIBUIDO and not outro_profissional_id:
        raise ErroRetrabalho("informe o outro profissional")
    mudancas: dict[str, Any] = {"estado": novo}
    if novo is E.RESOLVIDO:
        mudancas["atendido_em"] = agora
    if novo is E.REATRIBUIDO:
        mudancas["outro_profissional_id"] = outro_profissional_id
    return replace(retrabalho, **mudancas)


def marcar_nao_atendido_se_vencido(retrabalho: Retrabalho, agora: datetime) -> Retrabalho:
    """Para a rotina: devolve o retrabalho como nao_atendido (pronto p/ reatribuir) ou o mesmo."""
    if deve_virar_nao_atendido(retrabalho, agora):
        return transicionar(retrabalho, E.NAO_ATENDIDO, agora)
    return retrabalho
