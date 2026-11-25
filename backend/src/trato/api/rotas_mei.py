"""MEI do profissional: o app envia o CNPJ e lê o status. Cadastro e navegação seguem livres."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import exigir_papel
from trato.profissional.mei import RegistroMei, ServicoMei

router = APIRouter(prefix="/v1", tags=["mei"])
_PADRAO = ServicoMei()


def servico_mei(request: Request) -> ServicoMei:
    personalizado = getattr(request.app.state, "servico_mei", None)
    return personalizado if isinstance(personalizado, ServicoMei) else _PADRAO


class MeiIn(BaseModel):
    cnpj: str = Field(min_length=1, max_length=32, description="CNPJ, com ou sem pontuação.")


class MeiOut(BaseModel):
    cnpj: str | None = None
    mei_status: str = Field(description="nao_informado | pendente | valido | invalido")
    motivo: str = Field(description="Frase curta em português para mostrar ao profissional.")
    razao_social: str | None = None
    validado_em: datetime | None = None
    pode_orcar_e_receber: bool = Field(description="True quando o MEI está válido.")


def _saida(r: RegistroMei) -> MeiOut:
    return MeiOut(
        cnpj=r.cnpj,
        mei_status=r.mei_status.value,
        motivo=r.mei_motivo,
        razao_social=r.razao_social,
        validado_em=r.mei_validado_em,
        pode_orcar_e_receber=r.mei_status.value == "valido",
    )


@router.get("/profissional/mei", response_model=MeiOut, summary="Status do MEI")
def ler_mei(
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
) -> MeiOut:
    return _saida(servico_mei(request).status(usuario.id))


@router.put("/profissional/mei", response_model=MeiOut, summary="Informar o CNPJ do MEI")
def informar_mei(
    corpo: MeiIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
) -> MeiOut:
    return _saida(servico_mei(request).informar(usuario.id, corpo.cnpj))
