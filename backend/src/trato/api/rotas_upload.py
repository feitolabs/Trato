"""Upload seguro: `POST /v1/uploads` (URL de envio assinada) e `POST /v1/uploads/{id}/concluir`.

O app nunca grava no Storage por conta própria nem registra mídia: o backend emite a URL
assinada curta, e só depois de REVALIDAR o arquivo (tipo real, tamanho, EXIF/GPS, SHA-256) é que
registra em `midias` ou `verificacao_documentos`. Documento de verificação não volta ao dono.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, FastAPI, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictInt

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import (
    ContaBloqueada,
    Contexto,
    bloqueado_pode_no_pedido,
    exigir_papel,
    obter_contexto,
    usuario_ou_bloqueado,
)
from trato.api.repositorios_app import TIPOS_DOCUMENTO
from trato.api.visibilidade import pedido_visivel_ao_profissional
from trato.pedidos.estados import Estado, Pedido
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.upload import ErroUpload
from trato.uploads import ArmazenamentoArquivos
from trato.uploads.armazenamento import armazenamento_da_config
from trato.uploads.config import obter_config_uploads
from trato.uploads.servico import (
    DESTINOS,
    SO_CLIENTE,
    SO_PROFISSIONAL,
    RepositorioUploads,
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


router_fotos = APIRouter(prefix="/v1/pedidos", tags=["uploads"])
router_usuarios = APIRouter(prefix="/v1/usuarios", tags=["uploads"])

# Fotos que mostram o serviço (chegada, saída e as de antes/durante/depois). Foto de disputa,
# nota de material e anexo de chat têm regras próprias e não entram aqui.
FINALIDADES_DA_FOTO_DO_SERVICO = ("checkin", "antes", "durante", "depois", "checkout")
FINALIDADES_DA_FOTO_DO_PEDIDO = ("pedido", "antes")
URL_LEITURA_SEGUNDOS = 300


def urls_fotos_do_pedido(request: Request | None, pedido_id: str) -> list[str]:
    """URLs assinadas curtas das fotos anexadas na abertura do pedido."""
    if request is None:
        return []
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        return []
    urls: list[str] = []
    for m in servico.repo.midias_do_pedido(pedido_id, FINALIDADES_DA_FOTO_DO_PEDIDO):
        try:
            urls.append(
                servico.armazenamento.url_leitura(m.bucket, m.storage_path, URL_LEITURA_SEGUNDOS)
            )
        except Exception:  # noqa: BLE001,S112 - storage fora do ar não derruba a tela do pedido
            continue
    return urls


class FotoDoPedidoOut(BaseModel):
    id: str
    finalidade: str
    url: str = Field(description="URL assinada e curta para abrir a foto. Não guarde.")
    expira_em_segundos: int
    criada_em: datetime


@router_fotos.get(
    "/{pedido_id}/fotos",
    response_model=list[FotoDoPedidoOut],
    summary="Fotos do serviço (chegada, saída, antes e depois) ou fotos do pedido aberto",
    description=(
        "Sem `finalidade`, só cliente e profissional contratados veem as fotos do serviço. Com "
        "`finalidade=pedido`, inclui também profissionais elegíveis quando o pedido está aberto."
    ),
)
def fotos_do_pedido(
    pedido_id: str,
    finalidade: Annotated[str | None, Query()] = None,
    usuario: Usuario = Depends(_usuario),
    contexto: Contexto = Depends(obter_contexto),
    servico: ServicoUploads = Depends(obter_servico),
) -> list[FotoDoPedidoOut]:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    eh_parte = usuario.id in (pedido.cliente_id, pedido.profissional_id)
    if finalidade == "pedido":
        pode_ver_aberto = (
            pedido.estado is Estado.ABERTO
            and usuario.papel is PapelUsuario.PROFISSIONAL
            and pedido_visivel_ao_profissional(contexto, pedido.id, usuario.id) is not None
        )
        if not (eh_parte or pode_ver_aberto):
            raise HTTPException(404, "Pedido não encontrado.")
        finalidades = FINALIDADES_DA_FOTO_DO_PEDIDO
    elif finalidade is None:
        if not eh_parte:
            raise HTTPException(404, "Pedido não encontrado.")
        finalidades = FINALIDADES_DA_FOTO_DO_SERVICO
    else:
        raise HTTPException(422, "Finalidade desconhecida.")
    fotos: list[FotoDoPedidoOut] = []
    for m in servico.repo.midias_do_pedido(pedido.id, finalidades):
        try:
            url = servico.armazenamento.url_leitura(m.bucket, m.storage_path, URL_LEITURA_SEGUNDOS)
        except Exception:  # noqa: BLE001,S112 - storage fora do ar não derruba a tela do pedido
            continue
        fotos.append(
            FotoDoPedidoOut(
                id=m.id,
                finalidade=m.finalidade,
                url=url,
                expira_em_segundos=URL_LEITURA_SEGUNDOS,
                criada_em=m.criada_em,
            )
        )
    return fotos


class FotoDePerfilOut(BaseModel):
    url: str | None = Field(description="URL assinada e curta da foto; `null` se não tem foto.")
    expira_em_segundos: int = URL_LEITURA_SEGUNDOS


@router_usuarios.get(
    "/{usuario_id}/foto",
    response_model=FotoDePerfilOut,
    summary="Foto de perfil de um usuário (URL assinada curta)",
    description=(
        "Qualquer usuário logado pode pedir: a foto de perfil aparece para quem conversa, orça "
        "ou contrata com a pessoa. O id é um UUID que só aparece nessas telas. Sem foto, `url` "
        "vem `null` e o app mostra as iniciais."
    ),
)
def foto_de_perfil(
    usuario_id: str,
    usuario: Usuario = Depends(_usuario),
    servico: ServicoUploads = Depends(obter_servico),
) -> FotoDePerfilOut:
    caminho = servico.repo.foto_perfil(usuario_id)
    if not caminho:
        return FotoDePerfilOut(url=None)
    try:
        url = servico.armazenamento.url_leitura("avatar", caminho, URL_LEITURA_SEGUNDOS)
    except Exception:  # noqa: BLE001 - storage fora do ar: o app mostra as iniciais
        return FotoDePerfilOut(url=None)
    return FotoDePerfilOut(url=url)


@router_usuarios.get(
    "/{usuario_id}/portfolio/{upload_id}/foto",
    response_model=FotoDePerfilOut,
    summary="Foto de trabalho do portfólio de um profissional (URL assinada curta)",
    description=(
        "Qualquer usuário logado pode pedir: o portfólio é a vitrine pública do profissional. "
        "Só vale para envio de portfólio concluído do próprio dono; senão `url` vem `null`."
    ),
)
def foto_do_portfolio(
    usuario_id: str,
    upload_id: str,
    usuario: Usuario = Depends(_usuario),
    servico: ServicoUploads = Depends(obter_servico),
) -> FotoDePerfilOut:
    sol = servico.repo.solicitacao(upload_id)
    if (
        sol is None
        or sol.destino != "portfolio"
        or sol.status != "concluida"
        or str(sol.dono_id).replace("-", "") != str(usuario_id).replace("-", "")
    ):
        return FotoDePerfilOut(url=None)
    try:
        url = servico.armazenamento.url_leitura(sol.bucket, sol.caminho, URL_LEITURA_SEGUNDOS)
    except Exception:  # noqa: BLE001 - storage fora do ar: o app mostra o quadrado de foto
        return FotoDePerfilOut(url=None)
    return FotoDePerfilOut(url=url)


def _pode_no_chat_do_pedido(
    contexto: Contexto, pedido: Pedido, usuario: Usuario, destino: str = "chat"
) -> bool:
    """Parte do pedido, ou (só para anexo de chat) profissional que pode ver o pedido aberto e
    conversa sobre ele antes de ser contratado (mesma regra das mensagens)."""
    if usuario.id in (pedido.cliente_id, pedido.profissional_id):
        return True
    if destino != "chat" or usuario.papel is not PapelUsuario.PROFISSIONAL:
        return False
    return (
        pedido.estado is Estado.ABERTO
        and pedido_visivel_ao_profissional(contexto, pedido.id, usuario.id) is not None
    )


class AnexoChatOut(BaseModel):
    url: str = Field(description="URL assinada e curta da foto. Não guarde.")
    expira_em_segundos: int = URL_LEITURA_SEGUNDOS


@router_fotos.get(
    "/{pedido_id}/anexos-chat/{midia_id}",
    response_model=AnexoChatOut,
    summary="Foto enviada numa mensagem do chat (URL assinada curta)",
    description=(
        "Só quem participa da conversa do pedido. A mensagem leva `[Foto:<midia_id>]`; o app "
        "troca isso pela imagem com esta rota. O arquivo fica em bucket privado."
    ),
)
def anexo_do_chat(
    pedido_id: str,
    midia_id: str,
    usuario: Usuario = Depends(_usuario),
    contexto: Contexto = Depends(obter_contexto),
    servico: ServicoUploads = Depends(obter_servico),
) -> AnexoChatOut:
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None or not _pode_no_chat_do_pedido(contexto, pedido, usuario):
        raise HTTPException(404, "Pedido não encontrado.")
    midia = servico.repo.midia(midia_id)
    if midia is None or midia.pedido_id != pedido.id or midia.finalidade != "chat":
        raise HTTPException(404, "Foto não encontrada.")
    try:
        url = servico.armazenamento.url_leitura(
            midia.bucket, midia.storage_path, URL_LEITURA_SEGUNDOS
        )
    except Exception:  # noqa: BLE001 - storage fora do ar: o app mostra "Foto" sem a imagem
        raise HTTPException(503, "A foto não está disponível agora.") from None
    return AnexoChatOut(url=url)


def _pedido_do_envio(contexto: Contexto, corpo: PedirUploadIn, usuario: Usuario) -> Pedido:
    if not corpo.pedido_id:
        raise HTTPException(422, "Diga a qual pedido o arquivo pertence.")
    pedido = contexto.pedidos.obter(corpo.pedido_id)
    # Quem não é parte do pedido recebe 404, como nas demais rotas: nada de "existe, mas não é seu".
    if pedido is None or not _pode_no_chat_do_pedido(contexto, pedido, usuario, corpo.destino):
        raise HTTPException(404, "Pedido não encontrado.")
    eh_cliente = usuario.id == pedido.cliente_id
    if corpo.destino in SO_PROFISSIONAL and eh_cliente:
        raise HTTPException(403, "Só o profissional do pedido envia este tipo de arquivo.")
    if corpo.destino in SO_CLIENTE and not eh_cliente:
        raise HTTPException(403, "Só o cliente do pedido envia este tipo de arquivo.")
    return pedido


def _usuario_do_envio(
    usuario: Usuario = Depends(usuario_ou_bloqueado),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Conta bloqueada sem pedido próprio já contratado recebe 403 antes de qualquer outra
    resposta; com um, a rota ainda confere o destino e o pedido do envio."""
    if usuario.bloqueado and not any(
        bloqueado_pode_no_pedido(p, usuario.id)
        for p in contexto.pedidos.listar_do_usuario(usuario.id, True, limite=200)
    ):
        raise ContaBloqueada
    return usuario


def _exigir_envio_do_bloqueado(
    contexto: Contexto, usuario: Usuario, destino: str, pedido_id: str | None
) -> None:
    """Termos 20.6 e 20.10: conta bloqueada só envia a prova (`disputa`) do próprio pedido."""
    pedido = contexto.pedidos.obter(pedido_id) if pedido_id else None
    if destino != "disputa" or not bloqueado_pode_no_pedido(pedido, usuario.id):
        raise ContaBloqueada


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
    usuario: Usuario = Depends(_usuario_do_envio),
    contexto: Contexto = Depends(obter_contexto),
    servico: ServicoUploads = Depends(obter_servico),
) -> PedirUploadOut:
    if usuario.bloqueado:
        _exigir_envio_do_bloqueado(contexto, usuario, corpo.destino, corpo.pedido_id)
    regra = DESTINOS.get(corpo.destino)
    if regra is None:
        raise HTTPException(422, "Destino de arquivo desconhecido.")
    if (
        regra.registro == "portfolio"
        and usuario.papel is not PapelUsuario.PROFISSIONAL
        and not contexto.usuarios.tem_perfil_profissional(usuario.id)
    ):
        raise HTTPException(
            403, "Faça o cadastro de profissional antes de enviar fotos de portfólio."
        )
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
    usuario: Usuario = Depends(_usuario_do_envio),
    contexto: Contexto = Depends(obter_contexto),
    servico: ServicoUploads = Depends(obter_servico),
) -> ConcluirUploadOut:
    if usuario.bloqueado:
        envio = servico.repo.solicitacao(upload_id)
        if envio is None or str(envio.dono_id).replace("-", "") != usuario.id.replace("-", ""):
            raise ContaBloqueada
        _exigir_envio_do_bloqueado(contexto, usuario, envio.destino, envio.pedido_id)
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
    repo: RepositorioUploads | None = None,
) -> None:
    """Liga as rotas. Sem `armazenamento`, usa o Supabase Storage se houver configuração; sem
    nenhum dos dois, as rotas respondem 503 (nunca falam com o Storage real por acidente)."""
    from trato.api.contexto import agora_utc

    app.include_router(router)
    app.include_router(router_fotos)
    app.include_router(router_usuarios)
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
