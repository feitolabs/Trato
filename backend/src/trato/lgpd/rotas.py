"""Rotas de LGPD do titular: `/v1/me/dados`, `/v1/me/exclusao`, `/v1/me/consentimentos`,
`/v1/me/termos`."""

from __future__ import annotations

import threading
from contextlib import nullcontext
from datetime import date, datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from psycopg.errors import UndefinedColumn, UndefinedTable
from pydantic import BaseModel, ConfigDict, Field

from trato import legal
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.lgpd.servico import ErroLgpd, ServicoLgpd
from trato.persistencia.erros import ErroPersistencia
from trato.seguranca.cliente import ip_do_cliente

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
        jsonable_encoder(dados),
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
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, Any]:
    return servico.situacao_exclusao(usuario, contexto.agora())


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


# --- Aceite dos Termos (1.4, 1.7 e 23.4) ----------------------------------------------
# Nenhuma rota é bloqueada por aceite pendente: pela 23.4, continuar usando já é concordar.

_TRAVA_ACEITE = threading.Lock()


class SituacaoTermosOut(BaseModel):
    versao_vigente: str
    vigente_desde: date
    registro_disponivel: bool = Field(
        description="False: o histórico de aceites não existe no banco; não mostrar a tela."
    )
    aceite_pendente: bool
    versao_aceita: str | None = Field(None, description="Última versão com aceite registrado.")
    aceita_em: datetime | None = None


class AceitarTermosIn(_Entrada):
    versao: str = Field(
        min_length=1,
        max_length=40,
        description="A versão que o app MOSTROU à pessoa. Precisa ser a vigente.",
    )


def _vigente(contexto: Contexto) -> legal.VersaoDosTermos:
    vigente = legal.vigente_em(contexto.agora())
    if vigente is None:
        raise HTTPException(503, "Não há versão dos Termos disponível.")
    return vigente


def _sem_a_tabela(erro: ErroPersistencia) -> bool:
    return isinstance(erro.__cause__, UndefinedTable | UndefinedColumn)


def _situacao(
    servico: ServicoLgpd, usuario_id: str, vigente: legal.VersaoDosTermos
) -> SituacaoTermosOut:
    do_vigente = servico.aceite_dos_termos(usuario_id, vigente)
    ultimo = do_vigente or servico.ultimo_aceite_dos_termos(usuario_id)
    return SituacaoTermosOut(
        versao_vigente=vigente.versao,
        vigente_desde=vigente.vigente_desde,
        registro_disponivel=True,
        aceite_pendente=do_vigente is None,
        versao_aceita=ultimo.versao_texto if ultimo else None,
        aceita_em=ultimo.registrado_em if ultimo else None,
    )


@router.get(
    "/me/termos",
    response_model=SituacaoTermosOut,
    summary="Versão vigente dos Termos e se há aceite pendente",
)
def situacao_dos_termos(
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> SituacaoTermosOut:
    vigente = _vigente(contexto)
    try:
        return _situacao(servico, usuario.id, vigente)
    except ErroPersistencia as erro:
        if not _sem_a_tabela(erro):
            raise
        return SituacaoTermosOut(
            versao_vigente=vigente.versao,
            vigente_desde=vigente.vigente_desde,
            registro_disponivel=False,
            aceite_pendente=False,
        )


@router.post(
    "/me/termos/aceite",
    response_model=SituacaoTermosOut,
    status_code=201,
    summary="Registrar o aceite da versão vigente dos Termos",
    description="Repetir responde 200 com o primeiro registro (data e versão não mudam).",
)
def aceitar_os_termos(
    corpo: AceitarTermosIn,
    request: Request,
    response: Response,
    usuario: Usuario = Depends(usuario_atual),
    servico: ServicoLgpd = Depends(obter_servico),
    contexto: Contexto = Depends(obter_contexto),
) -> SituacaoTermosOut:
    vigente = _vigente(contexto)
    if corpo.versao != vigente.versao:
        raise HTTPException(
            409,
            f"A versão em vigor dos Termos é a {vigente.versao}. Mostre essa versão e "
            "peça o aceite de novo.",
        )
    seg = getattr(request.app.state, "seguranca", None)
    ip = ip_do_cliente(request, seg.config if seg else None)
    banco = contexto.extras.get("banco")
    try:
        # Duplo toque: um pedido por vez confere e grava (no banco, também entre servidores).
        with _TRAVA_ACEITE if banco is None else nullcontext():
            with banco.transacao() if banco is not None else nullcontext() as con:
                if con is not None:
                    con.execute(
                        "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                        (f"aceite-termos:{usuario.id}",),
                    )
                if servico.aceite_dos_termos(usuario.id, vigente) is not None:
                    response.status_code = 200
                else:
                    servico.registrar_consentimento(
                        usuario, "termos_de_uso", True, vigente.versao, contexto.agora(), ip
                    )
                return _situacao(servico, usuario.id, vigente)
    except ErroPersistencia as erro:
        if not _sem_a_tabela(erro):
            raise
        raise HTTPException(503, "O registro do aceite está indisponível agora.") from erro
