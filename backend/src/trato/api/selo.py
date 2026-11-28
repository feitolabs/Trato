"""Termos 10.3: o que muda enquanto o selo está retirado. Sem selo o profissional não envia
orçamento novo (o banco também recusa) e o nível só volta pela regularização."""

from __future__ import annotations

from typing import Any

from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse

ENVIO_BLOQUEADO = (
    "O seu selo de verificação foi retirado (Termos 10.3). Até a regularização não é possível "
    "enviar orçamentos novos. Para contestar, fale com o atendimento."
)
APROVACAO_BLOQUEADA = (
    "O selo deste profissional foi retirado (Termos 10.3). Regularize o selo antes de aprovar "
    "um nível de verificação."
)


class SeloRetiradoErro(HTTPException):
    codigo = "selo_retirado"

    def __init__(self, mensagem: str = ENVIO_BLOQUEADO) -> None:
        super().__init__(409, mensagem)


async def tratar_selo_retirado(_: Request, erro: SeloRetiradoErro) -> JSONResponse:
    return JSONResponse(
        status_code=erro.status_code, content={"detail": erro.detail, "codigo": erro.codigo}
    )


def selo_retirado(contexto: Any, profissional_id: str) -> bool:
    return contexto.selos.retirada_aberta(profissional_id)


def exigir_selo_para_orcar(contexto: Any, profissional_id: str) -> None:
    if selo_retirado(contexto, profissional_id):
        raise SeloRetiradoErro
