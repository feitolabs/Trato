"""Quem é avisado, com que título e corpo, em cada transição do pedido (NOT-1).

Função pura de planejamento: `planejar` só monta a lista; quem envia é o gancho
(`ganchos.criar_gancho`), que nunca derruba a transição. O corpo é português simples e nunca
leva código de início/conclusão nem dado pessoal. Prazos e datas vêm da configuração.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from trato.notificacoes.eventos import Evento
from trato.pedidos.estados import Acao, Pedido

log = logging.getLogger("trato.notificacoes")
_FUSO_BR = ZoneInfo("America/Sao_Paulo")

# ação -> (evento, para quem: "cliente" | "profissional" | "ambos") sem texto especial
SIMPLES: dict[Acao, tuple[Evento, str]] = {
    Acao.ACEITAR_ORCAMENTO: (Evento.ORCAMENTO_ACEITO, "profissional"),
    Acao.REGISTRAR_CLIENTE_AUSENTE: (Evento.CLIENTE_AUSENTE, "cliente"),
    Acao.ABRIR_DISPUTA: (Evento.DISPUTA_ABERTA, "ambos"),
    Acao.ENCERRAR_DISPUTA_POR_ACORDO: (Evento.DISPUTA_DECIDIDA, "ambos"),
    Acao.DECIDIR_DISPUTA: (Evento.DISPUTA_DECIDIDA, "ambos"),
}


@dataclass(frozen=True)
class Aviso:
    evento: Evento
    usuario_id: str
    chave: str
    titulo: str | None = None
    corpo: str | None = None


def _dia(instante: datetime) -> str:
    return instante.astimezone(_FUSO_BR).strftime("%d/%m/%Y")


def _hora(instante: datetime) -> str:
    return instante.astimezone(_FUSO_BR).strftime("%H:%M")


def texto_prazo(prazo: timedelta) -> str:
    """'48 horas' (até 3 dias) ou 'N dias'."""
    horas = int(prazo.total_seconds() // 3600)
    if horas <= 72 or horas % 24:
        return f"{horas} horas"
    return f"{horas // 24} dias"


def _ciclo(pedido: Pedido) -> str:
    """Muda a cada volta do fluxo (retrabalho): o aviso de cada ciclo vale uma vez."""
    base = pedido.check_out_em or pedido.concluido_em
    return str(int(base.timestamp())) if base is not None else "0"


def _janela(pedido: Pedido) -> str:
    j = pedido.janela
    if j is None:
        return ""
    return f" Serviço marcado para {_dia(j.inicio)}, das {_hora(j.inicio)} às {_hora(j.fim)}."


def _retrabalhos(contexto: Any, pedido_id: str) -> int:
    try:
        return len(contexto.garantias.retrabalhos(pedido_id))
    except Exception:  # noqa: BLE001 - só compõe a chave
        return 0


def _prazo_confirmacao(contexto: Any) -> timedelta | None:
    try:
        return contexto.config.carregar().prazos_pedido.confirmacao_cliente
    except Exception:  # noqa: BLE001 - sem configuração, o aviso sai sem o prazo
        return None


def _liberacao(contexto: Any, depois: Pedido) -> datetime | None:
    try:
        from trato.api.rotas_financeiro import liberacao_prevista  # import tardio: evita ciclo

        return liberacao_prevista(contexto, depois.concluido_em)
    except Exception:  # noqa: BLE001
        return None


def planejar(acao: Acao, depois: Pedido, contexto: Any) -> list[Aviso]:
    cliente = depois.cliente_id
    prof = depois.profissional_id
    pid = depois.id
    avisos: list[Aviso] = []

    def para(quem: str | None, evento: Evento, chave: str, **kw: Any) -> None:
        if quem:
            avisos.append(Aviso(evento, quem, chave, **kw))

    if acao in SIMPLES:
        evento, destino = SIMPLES[acao]
        if destino in ("cliente", "ambos"):
            para(cliente, evento, f"{pid}:{acao.value}")
        if destino in ("profissional", "ambos"):
            para(prof, evento, f"{pid}:{acao.value}")
    elif acao is Acao.CONFIRMAR_PAGAMENTO:
        chave = f"{pid}:{acao.value}"
        para(cliente, Evento.PAGAMENTO_CONFIRMADO, chave)
        para(
            prof,
            Evento.PAGAMENTO_CONFIRMADO,
            chave,
            titulo="Pagamento recebido",
            corpo="Pagamento recebido: o valor fica retido até o cliente confirmar o serviço.",
        )
    elif acao is Acao.CONFIRMAR_AGENDA:
        corpo = (
            "Abra o pedido para ver o código que o profissional vai pedir na chegada."
            + _janela(depois)
        )
        para(cliente, Evento.CODIGO_INICIO, f"{pid}:{acao.value}", corpo=corpo)
    elif acao is Acao.FAZER_CHECK_IN:
        para(cliente, Evento.SERVICO_INICIADO, f"{pid}:{acao.value}")
        para(cliente, Evento.CODIGO_CONCLUSAO, f"{pid}:{acao.value}")
    elif acao is Acao.FAZER_CHECK_OUT:
        prazo = _prazo_confirmacao(contexto)
        corpo = "O profissional terminou. Confirme se está tudo certo."
        if prazo is not None:
            corpo = (
                f"O profissional terminou. Você tem {texto_prazo(prazo)} para confirmar o "
                "serviço ou abrir uma reclamação."
            )
        para(cliente, Evento.CONCLUSAO_PARA_CONFIRMAR, f"{pid}:{acao.value}:{_ciclo(depois)}",
             corpo=corpo)  # fmt: skip
    elif acao is Acao.CONFIRMAR_CONCLUSAO:
        quando = _liberacao(contexto, depois)
        corpo = "O cliente confirmou o serviço."
        if quando is not None:
            corpo += f" A liberação do valor está prevista para {_dia(quando)}."
        para(prof, Evento.CLIENTE_CONFIRMOU, f"{pid}:{acao.value}:{_ciclo(depois)}", corpo=corpo)
    elif acao is Acao.PEDIR_RETRABALHO:
        para(prof, Evento.RETRABALHO, f"{pid}:{acao.value}:{_retrabalhos(contexto, pid)}")
    elif acao is Acao.RESOLVER_RETRABALHO:
        para(cliente, Evento.RETRABALHO_RESOLVIDO,
             f"{pid}:{acao.value}:{_retrabalhos(contexto, pid)}")  # fmt: skip
    return avisos
