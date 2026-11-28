"""Validade do orçamento (Termos 5.2, 5.3 e 6.3): vencido não é aceito, renegociado nem
cobrado. Orçamento sem validade (antigo) segue valendo."""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

# Orçamento antigo sem o campo: diz que não foi informado, sem inventar condição (5.2).
FORA_DO_ESCOPO_NAO_INFORMADO = (
    "O orçamento original não informou o que não está incluído. Confirme com o profissional "
    "antes de aceitar."
)
MENSAGEM = "Este orçamento venceu e perdeu o efeito (Termos 5.2). Peça um novo ao profissional."


class OrcamentoVencido(HTTPException):
    codigo = "orcamento_vencido"

    def __init__(self) -> None:
        super().__init__(409, MENSAGEM)


class OrcamentoIncompleto(HTTPException):
    """Orçamento antigo sem prazo, validade ou garantia: não gera versão nova (5.2)."""

    codigo = "orcamento_incompleto"

    def __init__(self) -> None:
        super().__init__(
            409,
            "Este orçamento é antigo e não tem prazo, validade e garantia (Termos 5.2). "
            "O profissional precisa enviar um orçamento novo com os três.",
        )


async def tratar_orcamento_vencido(
    _: Request, erro: OrcamentoVencido | OrcamentoIncompleto
) -> JSONResponse:
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
    return detalhe is not None and venceu(validade_vigente(contexto, detalhe), momento)


def validade_vigente(contexto: Any, detalhe: Any) -> datetime | None:
    """Validade do orçamento prorrogada pelas falhas do app ou do pagamento (22.3)."""
    from trato.api.indisponibilidade import ORIGENS_ORCAMENTO, prazo_vigente  # evita ciclo

    return prazo_vigente(
        contexto,
        ORIGENS_ORCAMENTO,
        _com_fuso(detalhe.enviado_em),
        _com_fuso(detalhe.validade_ate),
    )


def _com_fuso(momento: datetime | None) -> datetime | None:
    return momento.replace(tzinfo=UTC) if momento and momento.tzinfo is None else momento


def momento_da_confirmacao(payload: Mapping[str, Any], agora: datetime) -> datetime:
    """Quando o parceiro confirmou: o `created` do evento assinado (aviso atrasado não pune
    quem pagou a tempo). Sem ele, a hora em que o aviso chegou."""
    criado = payload.get("created")
    if isinstance(criado, int) and not isinstance(criado, bool) and criado > 0:
        return datetime.fromtimestamp(criado, UTC)
    return agora
