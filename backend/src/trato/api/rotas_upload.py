"""Upload seguro: `POST /v1/uploads` (URL de envio assinada) e `POST /v1/uploads/{id}/concluir`.

O app nunca grava no Storage por conta própria nem registra mídia: o backend emite a URL
assinada curta, e só depois de REVALIDAR o arquivo (tipo real, tamanho, EXIF/GPS, SHA-256) é que
registra em `midias` ou `verificacao_documentos`. Documento de verificação não volta ao dono.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.repositorios_app import TIPOS_DOCUMENTO
from trato.pedidos.estados import Pedido
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.upload import ErroUpload
from trato.uploads import ArmazenamentoArquivos
from trato.uploads.armazenamento import armazenamento_da_config
from trato.uploads.config import obter_config_uploads
from trato.uploads.servico import (
    DESTINOS,
    SO_CLIENTE,
    SO_PROFISSIONAL,
    ServicoUploads,
    SolicitacaoInvalida,
    UploadNegado,
    UploadsEmMemoria,
)

router = APIRouter(prefix="/v1/uploads", tags=["uploads"])

_usuario = exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)


class PedirUploadIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    destino: str = Field(description=f"Um de: {', '.join(DESTINOS)}.")
    nome_arquivo: str = Field(min_length=1, max_length=255)
    content_type: str = Field(min_length=3, max_length=100)
    tamanho_bytes: StrictInt = Field(gt=0, le=10**9)
    pedido_id: str | None = Field(None, description="Obrigatório nos destinos de pedido.")
    tipo_documento: str | None = Field(None, description="Obrigatório em `verificacao`.")


class PedirUploadOut(BaseModel):
    upload_id: str
    url_envio: str
    metodo: str = "PUT"
    expira_em_segundos: int
    content_type: str


class ConcluirUploadIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float | None = Field(None, ge=-90, le=90)
    longitude: float | None = Field(None, ge=-180, le=180)


class ConcluirUploadOut(BaseModel):
    upload_id: str
    destino: str
    status: str
    midia_id: str | None = Field(None, description="Id da mídia (use em check-in, disputa etc.).")
    sha256: str | None = None
    tamanho_bytes: int


def obter_servico(request: Request) -> ServicoUploads:
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        raise HTTPException(503, "O envio de arquivos ainda não foi ligado.")
    return servico


def _pedido_do_envio(contexto: Contexto, corpo: PedirUploadIn, usuario: Usuario) -> Pedido:
    if not corpo.pedido_id:
        raise HTTPException(422, "Diga a qual pedido o arquivo pertence.")
    pedido = contexto.pedidos.obter(corpo.pedido_id)
    # Quem não é parte do pedido recebe 404, como nas demais rotas: nada de "existe, mas não é seu".
    if pedido is None or usuario.id not in (pedido.cliente_id, pedido.profissional_id):
        raise HTTPException(404, "Pedido não encontrado.")
    eh_cliente = usuario.id == pedido.cliente_id
    if corpo.destino in SO_PROFISSIONAL and eh_cliente:
        raise HTTPException(403, "Só o profissional do pedido envia este tipo de arquivo.")
    if corpo.destino in SO_CLIENTE and not eh_cliente:
        raise HTTPException(403, "Só o cliente do pedido envia este tipo de arquivo.")
    return pedido


@router.post(
    "",
    response_model=PedirUploadOut,
    status_code=201,
    summary="Pedir a URL de envio assinada de um arquivo",
    description=(
        "Valida destino, tipo e tamanho e devolve uma URL de envio curta para um bucket privado. "
        "Depois de enviar, chame `/v1/uploads/{id}/concluir`: sem isso o arquivo não vale."
    ),
)
def pedir_upload(
    corpo: PedirUploadIn,
    usuario: Usuario = Depends(_usuario),
    contexto: Contexto = Depends(obter_contexto),
    servico: ServicoUploads = Depends(obter_servico),
) -> PedirUploadOut:
    regra = DESTINOS.get(corpo.destino)
    if regra is None:
        raise HTTPException(422, "Destino de arquivo desconhecido.")
    pedido_id = None
    if regra.registro == "midia":
        pedido_id = _pedido_do_envio(contexto, corpo, usuario).id
    elif corpo.pedido_id:
        raise HTTPException(422, "Este destino não é de um pedido.")
    if regra.registro == "documento" and corpo.tipo_documento not in TIPOS_DOCUMENTO:
        raise HTTPException(422, "Tipo de documento inválido.")
    try:
        sol, url = servico.pedir(
            usuario.id,
            corpo.destino,
            corpo.content_type,
            corpo.tamanho_bytes,
            corpo.nome_arquivo,
            pedido_id=pedido_id,
            tipo_documento=corpo.tipo_documento,
        )
    except ErroUpload as erro:
        raise HTTPException(422, str(erro)) from None
    return PedirUploadOut(
        upload_id=sol.id,
        url_envio=url,
        expira_em_segundos=servico.config.url_envio_segundos,
        content_type=sol.content_type,
    )


@router.post(
    "/{upload_id}/concluir",
    response_model=ConcluirUploadOut,
    summary="Concluir o envio: o backend revalida o arquivo e registra",
    description=(
        "Confere o tipo real pelo conteúdo, o tamanho, remove EXIF/GPS de imagens e calcula o "
        "SHA-256. Arquivo falso é apagado e recusado. Documento de verificação não devolve "
        "caminho nem link: só a equipe de cadastro o vê, por URL assinada curta e auditada."
    ),
)
def concluir_upload(
    upload_id: str,
    corpo: ConcluirUploadIn | None = None,
    usuario: Usuario = Depends(_usuario),
    servico: ServicoUploads = Depends(obter_servico),
) -> ConcluirUploadOut:
    try:
        sol = servico.concluir(
            usuario.id,
            upload_id,
            lat=corpo.latitude if corpo else None,
            lng=corpo.longitude if corpo else None,
        )
    except UploadNegado as erro:
        raise HTTPException(404, str(erro)) from None
    except SolicitacaoInvalida as erro:
        raise HTTPException(erro.status, str(erro)) from None
    midia = servico.repo.midia(sol.registro_id) if sol.registro_id else None
    return ConcluirUploadOut(
        upload_id=sol.id,
        destino=sol.destino,
        status=sol.status,
        midia_id=midia.id if midia else None,
        sha256=midia.sha256 if midia else None,
        tamanho_bytes=midia.tamanho_bytes if midia else sol.tamanho_bytes,
    )


def registrar_rotas(
    app: FastAPI,
    armazenamento: ArmazenamentoArquivos | None = None,
    repo: UploadsEmMemoria | None = None,
) -> None:
    """Liga as rotas. Sem `armazenamento`, usa o Supabase Storage se houver configuração; sem
    nenhum dos dois, as rotas respondem 503 (nunca falam com o Storage real por acidente)."""
    from trato.api.contexto import agora_utc

    app.include_router(router)
    armazenamento = armazenamento or armazenamento_da_config()
    if armazenamento is None:
        return

    def agora():  # type: ignore[no-untyped-def]
        contexto = getattr(app.state, "contexto", None)
        return contexto.agora() if contexto is not None else agora_utc()

    app.state.servico_uploads = ServicoUploads(
        armazenamento,
        repo or UploadsEmMemoria(),
        obter_config_seguranca(),
        obter_config_uploads(),
        agora,
    )
