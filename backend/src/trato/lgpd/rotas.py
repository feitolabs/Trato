"""Rotas de LGPD do titular: `/v1/me/dados`, `/v1/me/exclusao`, `/v1/me/consentimentos`."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.lgpd.servico import ErroLgpd, ServicoLgpd

router = APIRouter(prefix="/v1", tags=["lgpd"])


def obter_servico(request: Request) -> ServicoLgpd:
    servico = request.app.state.lgpd_fabrica(request.app)
    if servico is None:
        raise HTTPException(503, "LGPD ainda sem repositórios ligados neste ambiente.")
    return servico  # type: ignore[no-any-return]


def _erro(erro: ErroLgpd) -> HTTPException:
    return HTTPException(erro.status, str(erro))


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


@router.get(
    "/me/dados",
    summary="Exportar meus dados (LGPD)",
    description="Devolve em JSON tudo que o Trato guarda sobre você, mais o que fica por lei.",
)
def exportar_meus_dados(
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> JSONResponse:
    dados = servico.exportar(usuario, contexto.agora())
    return JSONResponse(
        dados,
        headers={"Content-Disposition": 'attachment; filename="meus-dados-trato.json"'},
    )


class ExclusaoIn(_Entrada):
    """Sem `token_confirmacao`: inicia o pedido. Com ele: confirma."""

    token_confirmacao: str | None = Field(default=None, max_length=200)


@router.post(
    "/me/exclusao",
    summary="Pedir (e depois confirmar) a exclusão da minha conta",
    description=(
        "Em dois passos. 1) Sem corpo: devolve o que será anonimizado e o que fica por lei, e um "
        "`token_confirmacao`. 2) Com o token: agenda a anonimização após a carência. Dá para "
        "cancelar com DELETE durante a carência."
    ),
)
def pedir_exclusao(
    corpo: ExclusaoIn | None = None,
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, Any]:
    try:
        if corpo is not None and corpo.token_confirmacao:
            return servico.confirmar_exclusao(usuario, corpo.token_confirmacao, contexto.agora())
        return servico.pedir_exclusao(usuario, contexto.agora())
    except ErroLgpd as erro:
        raise _erro(erro) from erro


@router.get("/me/exclusao", summary="Situação do meu pedido de exclusão")
def situacao_exclusao(
    usuario: Usuario = Depends(usuario_atual), servico: ServicoLgpd = Depends(obter_servico)
) -> dict[str, Any]:
    return servico.situacao_exclusao(usuario)


@router.delete("/me/exclusao", status_code=204, summary="Cancelar o pedido de exclusão")
def cancelar_exclusao(
    usuario: Usuario = Depends(usuario_atual), servico: ServicoLgpd = Depends(obter_servico)
) -> None:
    try:
        servico.cancelar_exclusao(usuario)
    except ErroLgpd as erro:
        raise _erro(erro) from erro


class ConsentimentoIn(_Entrada):
    finalidade: str = Field(min_length=1, max_length=60)
    aceito: bool
    versao_texto: str = Field(min_length=1, max_length=40)


class ConsentimentoOut(BaseModel):
    finalidade: str
    aceito: bool
    versao_texto: str
    registrado_em: datetime


@router.post(
    "/me/consentimentos",
    response_model=ConsentimentoOut,
    status_code=201,
    summary="Registrar (ou revogar) um consentimento",
)
def registrar_consentimento(
    corpo: ConsentimentoIn,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> ConsentimentoOut:
    ip = request.client.host if request.client else None
    try:
        linha = servico.registrar_consentimento(
            usuario, corpo.finalidade, corpo.aceito, corpo.versao_texto, contexto.agora(), ip
        )
    except ErroLgpd as erro:
        raise _erro(erro) from erro
    return ConsentimentoOut(
        finalidade=linha.finalidade,
        aceito=linha.aceito,
        versao_texto=linha.versao_texto,
        registrado_em=linha.registrado_em,
    )


@router.get("/me/consentimentos", summary="Meus consentimentos (vigentes e histórico)")
def meus_consentimentos(
    usuario: Usuario = Depends(usuario_atual), servico: ServicoLgpd = Depends(obter_servico)
) -> dict[str, Any]:
    return servico.consentimentos(usuario)


@router.post(
    "/lgpd/exclusoes/processar",
    summary="Anonimiza as exclusões que passaram da carência (equipe)",
)
def processar_exclusoes(
    _: Usuario = Depends(exigir_papel(PapelUsuario.EQUIPE)),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, int]:
    return servico.processar_vencidas(contexto.agora())
