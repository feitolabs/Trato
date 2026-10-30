"""Rotas de segurança: autorização de SMS (hook), identificadores, flags e validação de upload."""

from __future__ import annotations

import hmac
from dataclasses import asdict
from datetime import datetime
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.seguranca import upload
from trato.seguranca.duplicidade import DetectorDuplicidade
from trato.seguranca.estado import Seguranca
from trato.seguranca.flags import revisar
from trato.seguranca.sms import ProtecaoSms

router = APIRouter(prefix="/v1/seguranca", tags=["seguranca"])


def obter_seguranca(request: Request) -> Seguranca:
    return request.app.state.seguranca  # type: ignore[no-any-return]


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class SmsIn(_Entrada):
    telefone: str = Field(min_length=8, max_length=32)
    dispositivo: str | None = Field(default=None, max_length=128)
    ip: str | None = Field(default=None, max_length=64)


class SmsOut(BaseModel):
    permitido: bool
    motivo: str | None
    retry_apos_s: int


@router.post(
    "/sms/autorizar",
    response_model=SmsOut,
    summary="Autoriza (ou não) o envio de um SMS de confirmação",
    description=(
        "Chamada pelo Send SMS Hook ANTES de enviar. Exige o cabeçalho `X-Hook-Segredo`. "
        "Se não permitido, o hook não envia."
    ),
)
def autorizar_sms(
    corpo: SmsIn,
    seg: Seguranca = Depends(obter_seguranca),
    x_hook_segredo: Annotated[str | None, Header()] = None,
) -> SmsOut:
    esperado = seg.config.sms_hook_segredo.get_secret_value()
    if not esperado:
        raise HTTPException(503, "Autorização de SMS ainda não configurada.")
    if not x_hook_segredo or not hmac.compare_digest(x_hook_segredo, esperado):
        raise HTTPException(401, "Segredo do hook inválido.")
    decisao = ProtecaoSms(seg).autorizar(corpo.telefone, corpo.dispositivo, corpo.ip)
    return SmsOut(
        permitido=decisao.permitido, motivo=decisao.motivo, retry_apos_s=decisao.retry_apos_s
    )


class IdentificadoresIn(_Entrada):
    cpf: str | None = Field(default=None, max_length=20)
    telefone: str | None = Field(default=None, max_length=32)
    dispositivo: str | None = Field(default=None, max_length=128)


@router.post(
    "/identificadores",
    status_code=204,
    summary="Registra CPF, telefone e dispositivo do usuário para checar duplicidade",
    description=(
        "Sempre responde 204, sem dizer se achou duplicidade (não revela conta de outra pessoa). "
        "Se achar, abre uma flag para a equipe revisar; nada é bloqueado."
    ),
)
def registrar_identificadores(
    corpo: IdentificadoresIn,
    usuario: Usuario = Depends(usuario_atual),
    seg: Seguranca = Depends(obter_seguranca),
) -> Response:
    DetectorDuplicidade(seg, seg.identificadores).verificar(
        usuario.id, cpf=corpo.cpf, telefone=corpo.telefone, dispositivo=corpo.dispositivo
    )
    return Response(status_code=204)


class FlagOut(BaseModel):
    id: str
    tipo: str
    severidade: str
    usuario_id: str | None
    motivos: list[str]
    detalhes: dict[str, Any]
    status: str
    criada_em: datetime
    revisada_por: str | None
    revisada_em: datetime | None
    nota_revisao: str | None


def _flag_out(flag: Any) -> FlagOut:
    dados = asdict(flag)
    dados["motivos"] = list(flag.motivos)
    return FlagOut(**dados)


@router.get("/flags", response_model=list[FlagOut], summary="Flags para revisão humana (equipe)")
def listar_flags(
    status: Literal["aberta", "confirmada", "descartada"] | None = "aberta",
    _: Usuario = Depends(exigir_papel(PapelUsuario.EQUIPE)),
    seg: Seguranca = Depends(obter_seguranca),
) -> list[FlagOut]:
    return [_flag_out(f) for f in seg.flags.listar(status)]


class RevisaoIn(_Entrada):
    decisao: Literal["confirmar", "descartar"]
    nota: str | None = Field(default=None, max_length=1000)


@router.post(
    "/flags/{flag_id}/revisao",
    response_model=FlagOut,
    summary="Registra a decisão humana sobre uma flag",
    description="Só registra a revisão. Suspender ou bloquear conta é outra ação, da equipe.",
)
def revisar_flag(
    flag_id: str,
    corpo: RevisaoIn,
    equipe: Usuario = Depends(exigir_papel(PapelUsuario.EQUIPE)),
    seg: Seguranca = Depends(obter_seguranca),
    contexto: Contexto = Depends(obter_contexto),
) -> FlagOut:
    flag = revisar(seg.flags, flag_id, corpo.decisao, equipe.id, corpo.nota, contexto.agora())
    if flag is None:
        raise HTTPException(404, "Flag não encontrada.")
    seg.auditar(
        "antifraude.flag_revisada",
        ator_id=equipe.id,
        ator_tipo="equipe",
        depois={"flag": flag.id, "decisao": corpo.decisao},
        motivo=corpo.nota,
    )
    return _flag_out(flag)


class UploadIn(_Entrada):
    categoria: str = Field(max_length=40)
    content_type: str = Field(max_length=100)
    tamanho_bytes: int
    nome: str = Field(max_length=300)


class UploadOut(BaseModel):
    nome_seguro: str


@router.post(
    "/uploads/validar",
    response_model=UploadOut,
    summary="Valida tipo, tamanho e nome do arquivo ANTES do envio ao Storage",
)
def validar_upload(
    corpo: UploadIn,
    _: Usuario = Depends(usuario_atual),
    seg: Seguranca = Depends(obter_seguranca),
) -> UploadOut:
    try:
        nome = upload.validar_metadados(
            seg.config, corpo.categoria, corpo.content_type, corpo.tamanho_bytes, corpo.nome
        )
    except upload.ErroUpload as erro:
        raise HTTPException(422, str(erro)) from erro
    return UploadOut(nome_seguro=nome)
