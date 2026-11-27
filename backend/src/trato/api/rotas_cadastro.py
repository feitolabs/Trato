"""Cadastro: consulta do CPF antes de criar a conta e gravação do CPF depois do primeiro login.

Um CPF, uma conta (escopo 11.2). A consulta pública só diz se o CPF está livre; não diz de quem
é. A gravação é autenticada e a chave única de `usuarios_privados` fecha a corrida entre dois
cadastros simultâneos.
"""

from __future__ import annotations

from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel, ConfigDict, Field, field_validator

from trato.api.auth import Usuario
from trato.api.contexto import Contexto, bearer_opcional, obter_contexto, usuario_atual
from trato.persistencia.erros import DadosInvalidos, Duplicado
from trato.persistencia.retorno_conta import hmacs_de_identificadores
from trato.seguranca.config import ConfigSeguranca, obter_config_seguranca
from trato.seguranca.contadores import Contadores
from trato.seguranca.cpf import cpf_valido, normalizar_cpf

router = APIRouter(prefix="/v1", tags=["cadastro"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


def _validar_nascimento(v: date | None) -> date | None:
    if v is not None:
        hoje = date.today()
        if not (date(1900, 1, 1) <= v < hoje):
            raise ValueError("Data de nascimento inválida.")
        idade = hoje.year - v.year - ((hoje.month, hoje.day) < (v.month, v.day))
        if idade < 18:
            raise ValueError("O cadastro é exclusivo para maiores de 18 anos.")
    return v


class CpfIn(_Entrada):
    cpf: str = Field(min_length=11, max_length=14)
    telefone: str | None = Field(default=None, max_length=24)
    data_nascimento: date | None = None

    _chk_nasc = field_validator("data_nascimento")(_validar_nascimento)


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
    cpf: str | None = Field(default=None, min_length=11, max_length=14)
    telefone: str | None = Field(default=None, max_length=24)
    data_nascimento: date | None = None

    _chk_nasc = field_validator("data_nascimento")(_validar_nascimento)


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
    if contexto.retorno_conta.esta_impedido(hmacs_de_identificadores(cpf=cpf)):
        raise HTTPException(403, "Não é possível criar uma nova conta com estes dados.")
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
    summary="Vincula dados iniciais à conta recém-criada no Auth",
    description=(
        "Responde sempre 204, tenha gravado ou não (não revela se a conta existe). Com login, só "
        "grava os dados da própria conta. Sem login, só conta nova que nunca entrou; muitas "
        "tentativas para a mesma conta respondem 429. Só preenche o que está vazio."
    ),
)
def vincular_cadastro(
    corpo: VincularCadastroIn,
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(bearer_opcional),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    cpf: str | None = None
    if corpo.cpf is not None:
        cpf = normalizar_cpf(corpo.cpf)
        if not cpf_valido(cpf):
            raise DadosInvalidos("CPF inválido.")
    if contexto.retorno_conta.esta_impedido(
        hmacs_de_identificadores(cpf=cpf, email=corpo.email, telefone=corpo.telefone)
    ):
        raise HTTPException(403, "Não é possível criar uma nova conta com estes dados.")
    dados = (corpo.usuario_id, corpo.email, corpo.nome)
    token = credenciais.credentials if credenciais else None
    usuario = contexto.auth.autenticar(token) if token else None
    if usuario is not None:  # sessão válida: só a própria conta
        if _mesmo_id(usuario.id, corpo.usuario_id):
            contexto.usuarios.vincular_cadastro(*dados, cpf, corpo.telefone, corpo.data_nascimento)
        return Response(status_code=204)
    cfg = obter_config_seguranca()
    _limitar_por_conta(request, contexto, corpo.usuario_id, cfg)
    janela = timedelta(minutes=cfg.vincular_janela_conta_minutos)
    if not contexto.usuarios.pode_vincular_sem_sessao(
        corpo.usuario_id, corpo.email, contexto.agora(), janela
    ):
        return Response(status_code=204)
    try:
        contexto.usuarios.vincular_cadastro(*dados, cpf, corpo.telefone, corpo.data_nascimento)
    except Duplicado:  # CPF de outra conta: sem login a resposta não conta isso
        contexto.usuarios.vincular_cadastro(*dados, None, corpo.telefone, corpo.data_nascimento)
    return Response(status_code=204)


def _mesmo_id(a: str, b: str) -> bool:
    return a.replace("-", "").lower() == b.replace("-", "").lower()


def _limitar_por_conta(
    request: Request, contexto: Contexto, usuario_id: str, cfg: ConfigSeguranca
) -> None:
    """Tentativas sem login para a MESMA conta (o limite por IP já vale para todas). Conta igual
    exista ou não a conta. Em memória, por instância."""
    contadores = getattr(request.app.state, "tentativas_vinculo", None)
    if contadores is None:
        contadores = Contadores(lambda: contexto.agora().timestamp())
        request.app.state.tentativas_vinculo = contadores
    chave = f"vinculo:{usuario_id.replace('-', '').lower()}"
    if contadores.quantos(chave, cfg.vincular_janela_tentativas_s) >= cfg.vincular_max_por_conta:
        raise HTTPException(429, "Muitas tentativas. Tente de novo mais tarde.")
    contadores.adicionar(chave)


@router.post(
    "/me/cpf",
    status_code=204,
    summary="Gravar o meu CPF (uma vez)",
    description=(
        "Grava CPF e data de nascimento após o cadastro. O CPF é gravado só uma vez; repetir com "
        "o mesmo CPF não muda nada. CPF de outra conta responde 409."
    ),
)
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
    if contexto.retorno_conta.esta_impedido(
        hmacs_de_identificadores(cpf=cpf, telefone=corpo.telefone)
    ):
        raise HTTPException(403, "Não é possível concluir o cadastro com estes dados.")
    contexto.usuarios.garantir(usuario.id)
    contexto.usuarios.registrar_dados_privados(
        usuario.id, cpf, corpo.telefone, corpo.data_nascimento
    )
    return Response(status_code=204)
