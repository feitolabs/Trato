"""CNPJ do profissional (MEI ou outro CNPJ ativo): o app envia o CNPJ e lê o status."""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_atual
from trato.profissional.mei import PerfilInexistente, RegistroMei, ServicoMei, StatusMei

router = APIRouter(prefix="/v1", tags=["mei"])
_PADRAO = ServicoMei()


def profissional_ou_em_analise(
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Profissional aprovado ou com cadastro EM ANÁLISE (ainda tratado como cliente). Perfil
    recusado, suspenso ou sem perfil recebe 403. Só vale para esta rota."""
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        return usuario
    if (
        usuario.papel is PapelUsuario.CLIENTE
        and contexto.usuarios.status_perfil_profissional(usuario.id) == "em_analise"
    ):
        return usuario
    raise HTTPException(403, "Seu perfil não pode fazer isso.")


def servico_mei(request: Request) -> ServicoMei:
    personalizado = getattr(request.app.state, "servico_mei", None)
    if isinstance(personalizado, ServicoMei):
        return personalizado
    banco = getattr(request.app.state, "contexto", None)
    banco = banco.extras.get("banco") if banco is not None else None
    if banco is not None:  # produção: o MEI mora no Postgres, não na memória do processo
        from trato.persistencia.mei import MeiPostgres

        request.app.state.servico_mei = ServicoMei(repo=MeiPostgres(banco))
        return request.app.state.servico_mei
    return _PADRAO


class MeiIn(BaseModel):
    cnpj: str = Field(min_length=1, max_length=32, description="CNPJ, com ou sem pontuação.")


class MeiOut(BaseModel):
    cnpj: str | None = None
    mei_status: str = Field(description="nao_informado | pendente | valido | invalido")
    motivo: str = Field(description="Frase curta em português para mostrar ao profissional.")
    razao_social: str | None = None
    tipo_cnpj: str | None = Field(
        None, description='"mei" (optante MEI) ou "outro"; null se não valido.'
    )
    validado_em: datetime | None = None
    pode_orcar_e_receber: bool = Field(description="True quando o MEI está válido.")


def _saida(r: RegistroMei) -> MeiOut:
    return MeiOut(
        cnpj=r.cnpj,
        mei_status=r.mei_status.value,
        motivo=r.mei_motivo,
        razao_social=r.razao_social,
        tipo_cnpj=r.tipo_cnpj,
        validado_em=r.mei_validado_em,
        pode_orcar_e_receber=r.mei_status.value == "valido",
    )


@router.get("/profissional/mei", response_model=MeiOut, summary="Status do MEI")
def ler_mei(
    request: Request,
    usuario: Usuario = Depends(profissional_ou_em_analise),
) -> MeiOut:
    return _saida(servico_mei(request).status(usuario.id))


@router.put("/profissional/mei", response_model=MeiOut, summary="Informar o CNPJ do MEI")
def informar_mei(
    corpo: MeiIn,
    request: Request,
    usuario: Usuario = Depends(profissional_ou_em_analise),
) -> MeiOut:
    try:
        registro = servico_mei(request).informar(usuario.id, corpo.cnpj)
    except PerfilInexistente:
        raise HTTPException(
            409, "Complete seu cadastro de profissional antes de informar o CNPJ."
        ) from None
    if registro.mei_status is StatusMei.INVALIDO:
        # 422 com o motivo; o texto de "CNPJ em uso por outra conta" é o mesmo de "não validado".
        raise HTTPException(422, registro.mei_motivo)
    return _saida(registro)
