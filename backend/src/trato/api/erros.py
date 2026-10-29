"""Traduz erros das regras puras em respostas 4xx claras, em português."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from trato import disputas, garantias
from trato.financeiro import ledger
from trato.pedidos import estados

# Do mais específico para o mais geral: vale o primeiro que casar.
_STATUS: tuple[tuple[type[Exception], int], ...] = (
    (estados.AtorNaoAutorizado, 403),
    (estados.EstadoInvalido, 409),
    (estados.ForaDoPrazo, 409),
    (estados.ProvaInvalida, 422),
    (estados.PrazoNaoConfigurado, 503),
    (estados.TransicaoInvalida, 409),
    (disputas.AlcadaInvalida, 403),
    (disputas.PrazoExpirado, 409),
    (disputas.ResultadoInvalido, 422),
    (disputas.TransicaoInvalida, 409),
    (garantias.ErroRetrabalho, 409),
    (garantias.ErroGarantia, 409),
    (ledger.LancamentoInvalido, 422),
    (ledger.LedgerErro, 409),
)


def _resposta(request: Request, erro: Exception) -> JSONResponse:
    for tipo, status in _STATUS:
        if isinstance(erro, tipo):
            return JSONResponse({"detail": str(erro)}, status_code=status)
    raise erro


def instalar_tratadores(app: FastAPI) -> None:
    for tipo in (
        estados.TransicaoInvalida,
        disputas.DisputaErro,
        garantias.ErroRetrabalho,
        garantias.ErroGarantia,
        ledger.LedgerErro,
    ):
        app.add_exception_handler(tipo, _resposta)
