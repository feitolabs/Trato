"""Termos 13.4 e I.5: aviso antes de os Tratinhos vencerem.

Um aviso por pessoa, carteira e dia de vencimento (fuso America/Sao_Paulo); repetir a rotina não
duplica. Conta só o que SOBROU de cada crédito. Vale também com o programa desligado: o que já
foi creditado continua válido até o vencimento.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta
from typing import Any

from trato.api.moedas_saldo import creditos_validos
from trato.financeiro.periodo import BRASILIA
from trato.notificacoes.eventos import Evento

log = logging.getLogger("trato.moedas")
# Mínimo do Anexo I.5: a configuração pode antecipar o aviso, nunca encurtar.
ANTECEDENCIA_MINIMA_DIAS = 7
ANTECEDENCIA_MAXIMA_DIAS = 30  # teto da definição no banco (seed dos avisos prévios)


def antecedencia_dias(contexto: Any) -> int:
    valor = contexto.config.carregar().tratinhos_aviso_vencimento_dias
    if isinstance(valor, bool) or not isinstance(valor, int):
        return ANTECEDENCIA_MINIMA_DIAS
    return min(max(valor, ANTECEDENCIA_MINIMA_DIAS), ANTECEDENCIA_MAXIMA_DIAS)


def avisar_vencimentos(contexto: Any, notificador: Any, agora: datetime) -> int:
    """Devolve quantos vencimentos ganharam aviso novo."""
    if notificador is None:
        return 0
    ate = agora + timedelta(days=antecedencia_dias(contexto))
    novos = 0
    for usuario_id, carteira in contexto.moedas.carteiras_vencendo(agora, ate):
        try:
            por_dia: dict[date, int] = {}
            lancamentos = contexto.moedas.lancamentos_da_carteira(usuario_id, carteira)
            for parcela in creditos_validos(lancamentos, agora):
                if parcela.expira_em is not None and parcela.expira_em <= ate:
                    dia = parcela.expira_em.astimezone(BRASILIA).date()
                    por_dia[dia] = por_dia.get(dia, 0) + parcela.quantidade
            for dia, quantidade in sorted(por_dia.items()):
                criadas = notificador.notificar(
                    Evento.TRATINHOS_VENCENDO,
                    usuario_id,
                    chave=f"tratinhos:{carteira}:{dia.isoformat()}",
                    corpo=f"Você tem {quantidade} Tratinhos que vencem em {dia:%d/%m/%Y}.",
                    dados={"carteira": carteira, "vence_em": dia.isoformat()},
                    papel=carteira,
                )
                novos += bool(criadas)
        except Exception:  # noqa: BLE001 - uma carteira com erro não segura as outras
            log.exception("Aviso de vencimento de Tratinhos falhou (%s)", usuario_id)
    return novos
