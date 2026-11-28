"""Prazos exibidos ao cliente na cobrança Pix (Termos 6.3) e no estorno (Termos 6.10).

Funções puras: leem configuração quando existir e caem no padrão sem quebrar."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime, timedelta
from typing import Any

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import CobrancaLocal, EstadoCobranca, OrdemEstorno

PIX_VALIDADE_PADRAO_MINUTOS = 30
PRAZO_ESTORNO_PIX = "Pix: até 1 dia útil após a confirmação do estorno."
PRAZO_ESTORNO_CARTAO = (
    "Cartão de crédito: de 7 a 15 dias úteis, podendo aparecer em até 2 faturas conforme a "
    "administradora."
)


def validade_pix_minutos(cobranca: CobrancaLocal, contexto: Any | None = None) -> int | None:
    """Validade do QR code Pix em minutos (Termos 6.3). None para outros meios."""
    if cobranca.meio is not MeioPagamento.PIX:
        return None
    if contexto is not None:
        if cobranca.moedas_usadas > 0:
            try:
                mins = int(contexto.moedas.config().reserva_minutos)
                if mins > 0:
                    return mins
            except Exception:  # noqa: BLE001, S110 - campo informativo
                pass
        try:
            configurado = contexto.config.parametro_inteiro("pix_validade_minutos")
            if configurado and configurado > 0:
                return int(configurado)
        except Exception:  # noqa: BLE001, S110 - campo informativo
            pass
    return PIX_VALIDADE_PADRAO_MINUTOS


def dados_pix_cobranca(
    cobranca: CobrancaLocal | None, contexto: Any | None = None
) -> tuple[datetime | None, int | None]:
    """(pix_expira_em, pix_validade_minutos) para cobranças Pix; (None, None) caso contrário."""
    if cobranca is None or cobranca.meio is not MeioPagamento.PIX:
        return None, None
    minutos = validade_pix_minutos(cobranca, contexto)
    if minutos is None:
        return None, None
    return cobranca.criada_em + timedelta(minutes=minutos), minutos


def prazo_estimado_estorno(meio: MeioPagamento | None) -> str:
    """Prazo estimado do estorno conforme o meio de pagamento (Termos 6.10)."""
    return PRAZO_ESTORNO_PIX if meio is MeioPagamento.PIX else PRAZO_ESTORNO_CARTAO


def dados_estorno(
    cobranca: CobrancaLocal | None,
    ordens: Sequence[OrdemEstorno] = (),
) -> tuple[str | None, str | None]:
    """(estorno_status, estorno_prazo_estimado) para a cobrança/pedido (Termos 6.10).

    Status possíveis: `solicitado`, `em_processamento`, `concluido`, `falhou` (ou `None` se não
    houver estorno)."""
    relevantes = (
        [o for o in ordens if cobranca is None or o.cobranca_id == cobranca.id] if ordens else []
    )
    status: str | None = None
    if any(o.estado == "pendente" for o in relevantes):
        status = "solicitado"
    elif any(o.estado == "falhou" for o in relevantes):
        status = "falhou"
    elif any(o.estado == "enviada" for o in relevantes):
        if cobranca is not None and (
            cobranca.estornado_centavos > 0 or cobranca.status is EstadoCobranca.DEVOLVIDA
        ):
            status = "concluido"
        else:
            status = "em_processamento"
    elif cobranca is not None and (
        cobranca.estornado_centavos > 0 or cobranca.status is EstadoCobranca.DEVOLVIDA
    ):
        status = "concluido"
    if status is None:
        return None, None
    meio = cobranca.meio if cobranca is not None else None
    return status, prazo_estimado_estorno(meio)
