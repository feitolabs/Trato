"""Validade do orçamento (Termos 5.2, 5.3 e 6.3): vencido não é aceito, renegociado nem
cobrado. Orçamento sem validade (antigo) segue valendo."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

MENSAGEM = "Este orçamento venceu e perdeu o efeito (Termos 5.2). Peça um novo ao profissional."


class OrcamentoVencido(HTTPException):
    codigo = "orcamento_vencido"

    def __init__(self) -> None:
        super().__init__(409, MENSAGEM)


async def tratar_orcamento_vencido(_: Request, erro: OrcamentoVencido) -> JSONResponse:
    return JSONResponse(
        status_code=erro.status_code, content={"detail": erro.detail, "codigo": erro.codigo}
    )


def venceu(validade_ate: datetime | None, momento: datetime) -> bool:
    """No instante exato da validade já venceu. Data sem fuso é lida como UTC (como o banco)."""
    if validade_ate is None:
        return False
    if validade_ate.tzinfo is None:
        validade_ate = validade_ate.replace(tzinfo=UTC)
    return validade_ate <= momento


def orcamento_vencido(contexto: Any, orcamento_id: str | None, momento: datetime) -> bool:
    detalhe = contexto.orcamentos.detalhe(orcamento_id) if orcamento_id else None
    return detalhe is not None and venceu(detalhe.validade_ate, momento)


def momento_da_confirmacao(payload: Mapping[str, Any], agora: datetime) -> datetime:
    """Quando o parceiro confirmou: o `created` do evento assinado (aviso atrasado não pune
    quem pagou a tempo). Sem ele, a hora em que o aviso chegou."""
    criado = payload.get("created")
    if isinstance(criado, int) and not isinstance(criado, bool) and criado > 0:
        return datetime.fromtimestamp(criado, UTC)
    return agora
