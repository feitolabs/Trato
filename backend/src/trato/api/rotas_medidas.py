"""Minhas medidas e contestação (Termos 20.4 e 20.5). Conta bloqueada também entra aqui."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from trato.api import medidas as regras
from trato.api import medidas_anexos as provas
from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto
from trato.api.rotas_sac import usuario_do_suporte

router = APIRouter(prefix="/v1/me/medidas", tags=["medidas de conta"])


class ContestarIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    versao: str = Field(min_length=1, max_length=4000, description="A sua versão dos fatos.")
    anexos: list[str] = Field(
        default_factory=list,
        max_length=provas.MAXIMO_DE_ANEXOS,
        description="`anexo_id` dos arquivos já enviados.",
    )


def _erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


def _indisponivel() -> JSONResponse:
    return _erro(
        503, "indisponivel", "As medidas estão indisponíveis no momento. Fale com o atendimento."
    )


@router.get("", response_model=list[regras.MedidaOut], summary="Medidas na minha conta")
def minhas(
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    itens, _ = contexto.medidas.listar(usuario_id=usuario.id)
    return [regras.saida(contexto, m) for m in itens]


@router.post(
    "/{medida_id}/contestacao",
    response_model=regras.MedidaOut,
    summary="Contestar a medida (até 30 dias do aviso)",
)
def contestar(
    medida_id: str,
    corpo: ContestarIn,
    request: Request,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None or medida.usuario_id.replace("-", "") != usuario.id.replace("-", ""):
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    versao = corpo.versao.strip()
    if not versao:
        return _erro(422, "versao_vazia", "Conte a sua versão.")
    try:
        provas.contestar(
            contexto,
            getattr(request.app.state, "servico_uploads", None),
            medida,
            versao,
            "app",
            corpo.anexos,
        )
    except provas.ErroDeContestacao as erro:
        return _erro(erro.status, erro.codigo, erro.mensagem)
    return regras.saida(contexto, medida)


@router.post(
    "/{medida_id}/contestacao/anexos",
    response_model=provas.AnexoParaEnvioOut,
    status_code=201,
    summary="Pedir o envio de uma prova da contestação",
)
def pedir_anexo(
    medida_id: str,
    corpo: provas.PedirAnexoIn,
    request: Request,
    usuario: Usuario = Depends(usuario_do_suporte),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None or medida.usuario_id.replace("-", "") != usuario.id.replace("-", ""):
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    try:
        return provas.pedir_envio(
            contexto, getattr(request.app.state, "servico_uploads", None), medida, corpo
        )
    except provas.ErroDeContestacao as erro:
        return _erro(erro.status, erro.codigo, erro.mensagem)
