"""Cadastro: consulta do CPF antes de criar a conta e gravação do CPF depois do primeiro login.

Um CPF, uma conta (escopo 11.2). A consulta pública só diz se o CPF está livre; não diz de quem
é. A gravação é autenticada e a chave única de `usuarios_privados` fecha a corrida entre dois
cadastros simultâneos.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import Usuario
from trato.api.contexto import Contexto, obter_contexto, usuario_atual
from trato.persistencia.erros import DadosInvalidos
from trato.seguranca.cpf import cpf_valido, normalizar_cpf

router = APIRouter(prefix="/v1", tags=["cadastro"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CpfIn(_Entrada):
    cpf: str = Field(min_length=11, max_length=14)
    telefone: str | None = Field(default=None, max_length=24)


class CpfDisponivelOut(BaseModel):
    disponivel: bool


class IdentificadorIn(_Entrada):
    identificador: str = Field(min_length=10, max_length=24)


class IdentificadorOut(BaseModel):
    email: str | None


class VincularCadastroIn(_Entrada):
    usuario_id: str = Field(min_length=1, max_length=64)
    email: str = Field(min_length=3, max_length=254)
    nome: str = Field(default="", max_length=120)
    cpf: str = Field(min_length=11, max_length=14)
    telefone: str | None = Field(default=None, max_length=24)


@router.post(
    "/cadastro/cpf",
    response_model=CpfDisponivelOut,
    summary="O CPF está livre para uma conta nova?",
    description=(
        "Chamada pelo app antes de criar a conta. Responde só `disponivel`; nunca revela de quem "
        "é o CPF. A rota tem limite de tentativas por IP."
    ),
)
def consultar_cpf(corpo: CpfIn, contexto: Contexto = Depends(obter_contexto)) -> CpfDisponivelOut:
    cpf = normalizar_cpf(corpo.cpf)
    if not cpf_valido(cpf):
        raise DadosInvalidos("CPF inválido.")
    return CpfDisponivelOut(disponivel=contexto.usuarios.cpf_disponivel(cpf))


@router.post(
    "/cadastro/identificador",
    response_model=IdentificadorOut,
    summary="Resolve CPF ou telefone para o e-mail de login",
)
def resolver_identificador(
    corpo: IdentificadorIn, contexto: Contexto = Depends(obter_contexto)
) -> IdentificadorOut:
    digitos = "".join(c for c in corpo.identificador if c.isdigit())
    if len(digitos) < 10 or len(digitos) > 13:
        raise DadosInvalidos("Informe um CPF ou telefone válido.")
    return IdentificadorOut(email=contexto.usuarios.email_por_identificador(digitos))


@router.post(
    "/cadastro/vincular",
    status_code=204,
    summary="Vincula CPF e telefone à conta recém-criada no Auth",
)
def vincular_cadastro(
    corpo: VincularCadastroIn, contexto: Contexto = Depends(obter_contexto)
) -> Response:
    cpf = normalizar_cpf(corpo.cpf)
    if not cpf_valido(cpf):
        raise DadosInvalidos("CPF inválido.")
    contexto.usuarios.vincular_cadastro(
        corpo.usuario_id,
        corpo.email,
        corpo.nome,
        cpf,
        corpo.telefone,
    )
    return Response(status_code=204)


@router.post(
    "/me/dados-pessoais",
    status_code=204,
    summary="Gravar o meu CPF (uma vez, no cadastro)",
    description=(
        "Depois do primeiro login. O CPF é gravado só uma vez; repetir com o mesmo CPF não muda "
        "nada. CPF de outra conta responde 409."
    ),
)
def registrar_cpf(
    corpo: CpfIn,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    cpf = normalizar_cpf(corpo.cpf)
    if not cpf_valido(cpf):
        raise DadosInvalidos("CPF inválido.")
    contexto.usuarios.garantir(usuario.id)
    contexto.usuarios.registrar_dados_privados(usuario.id, cpf, corpo.telefone)
    return Response(status_code=204)
