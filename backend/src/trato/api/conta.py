"""Conta do usuário: dados pessoais, endereços salvos, favoritos e contatos de confiança.

Rotas `/v1/me/...`. Só o dono lê e muda os próprios dados; o id vem do token, nunca do corpo.
A versão em memória está aqui (padrão e testes); a do Postgres, em `persistencia/conta.py`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, replace
from datetime import date
from itertools import count
from typing import Protocol

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field, field_validator

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.persistencia.erros import Duplicado

LIMITE_ENDERECOS = 10
LIMITE_CONTATOS = 5


@dataclass(frozen=True)
class DadosPessoais:
    nome: str | None
    email: str | None
    cpf_final: str | None  # só os 2 últimos dígitos; o CPF inteiro nunca sai do backend
    telefone: str | None
    data_nascimento: date | None


@dataclass(frozen=True)
class Endereco:
    id: str
    apelido: str
    cep: str
    logradouro: str
    numero: str
    complemento: str | None
    bairro: str
    cidade: str
    uf: str
    principal: bool


@dataclass(frozen=True)
class Favorito:
    profissional_id: str
    nome: str | None
    nota_publica: float | None
    servicos_concluidos: int | None


@dataclass(frozen=True)
class ContatoConfianca:
    id: str
    nome: str
    telefone: str
    parentesco: str | None


class RepositorioConta(Protocol):
    def dados(self, usuario_id: str) -> DadosPessoais: ...

    def atualizar_dados(
        self,
        usuario_id: str,
        *,
        telefone: str | None,
        data_nascimento: date | None,
        limpar_telefone: bool,
        limpar_nascimento: bool,
    ) -> DadosPessoais: ...

    def enderecos(self, usuario_id: str) -> list[Endereco]: ...

    def salvar_endereco(self, usuario_id: str, endereco: Endereco) -> Endereco: ...

    def remover_endereco(self, usuario_id: str, endereco_id: str) -> bool: ...

    def favoritos(self, usuario_id: str) -> list[Favorito]: ...

    def favoritar(self, usuario_id: str, profissional_id: str) -> bool: ...

    def desfavoritar(self, usuario_id: str, profissional_id: str) -> None: ...

    def contatos(self, usuario_id: str) -> list[ContatoConfianca]: ...

    def salvar_contato(self, usuario_id: str, contato: ContatoConfianca) -> ContatoConfianca: ...

    def remover_contato(self, usuario_id: str, contato_id: str) -> bool: ...


class LimiteAtingido(Exception):
    """Passou do limite de endereços ou contatos (a rota responde 409)."""


class ContaEmMemoria:
    """Mesma regra do Postgres, sem banco (testes e modo sem persistência)."""

    def __init__(self) -> None:
        self._dados: dict[str, DadosPessoais] = {}
        self._enderecos: dict[str, list[Endereco]] = {}
        self._favoritos: dict[str, list[Favorito]] = {}
        self._contatos: dict[str, list[ContatoConfianca]] = {}
        self._telefones: dict[str, str] = {}
        self._ids = count(1)
        self.profissionais_existentes: set[str] | None = None  # None = qualquer id vale

    def dados(self, usuario_id: str) -> DadosPessoais:
        return self._dados.get(usuario_id, DadosPessoais(None, None, None, None, None))

    def atualizar_dados(
        self,
        usuario_id: str,
        *,
        telefone: str | None,
        data_nascimento: date | None,
        limpar_telefone: bool,
        limpar_nascimento: bool,
    ) -> DadosPessoais:
        atual = self.dados(usuario_id)
        if limpar_telefone:
            telefone = None
        elif telefone is None:
            telefone = atual.telefone
        if limpar_nascimento:
            data_nascimento = None
        elif data_nascimento is None:
            data_nascimento = atual.data_nascimento
        if telefone and self._telefones.get(telefone, usuario_id) != usuario_id:
            raise Duplicado("Esse telefone já está em outra conta.")
        if atual.telefone:
            self._telefones.pop(atual.telefone, None)
        if telefone:
            self._telefones[telefone] = usuario_id
        novo = replace(atual, telefone=telefone, data_nascimento=data_nascimento)
        self._dados[usuario_id] = novo
        return novo

    def enderecos(self, usuario_id: str) -> list[Endereco]:
        return list(self._enderecos.get(usuario_id, ()))

    def salvar_endereco(self, usuario_id: str, endereco: Endereco) -> Endereco:
        lista = self._enderecos.setdefault(usuario_id, [])
        existente = next((e for e in lista if e.id == endereco.id), None)
        if existente is None:
            if len(lista) >= LIMITE_ENDERECOS:
                raise LimiteAtingido(f"Você pode salvar até {LIMITE_ENDERECOS} endereços.")
            endereco = replace(endereco, id=f"end-{next(self._ids)}", principal=not lista)
            lista.append(endereco)
        else:
            lista[lista.index(existente)] = endereco
        if endereco.principal:
            lista[:] = [replace(e, principal=e.id == endereco.id) for e in lista]
        return next(e for e in lista if e.id == endereco.id)

    def remover_endereco(self, usuario_id: str, endereco_id: str) -> bool:
        lista = self._enderecos.get(usuario_id, [])
        restante = [e for e in lista if e.id != endereco_id]
        if len(restante) == len(lista):
            return False
        if restante and not any(e.principal for e in restante):
            restante[0] = replace(restante[0], principal=True)
        self._enderecos[usuario_id] = restante
        return True

    def favoritos(self, usuario_id: str) -> list[Favorito]:
        return list(self._favoritos.get(usuario_id, ()))

    def favoritar(self, usuario_id: str, profissional_id: str) -> bool:
        if (
            self.profissionais_existentes is not None
            and profissional_id not in self.profissionais_existentes
        ):
            return False
        lista = self._favoritos.setdefault(usuario_id, [])
        if all(f.profissional_id != profissional_id for f in lista):
            lista.insert(0, Favorito(profissional_id, None, None, None))
        return True

    def desfavoritar(self, usuario_id: str, profissional_id: str) -> None:
        self._favoritos[usuario_id] = [
            f for f in self._favoritos.get(usuario_id, []) if f.profissional_id != profissional_id
        ]

    def contatos(self, usuario_id: str) -> list[ContatoConfianca]:
        return list(self._contatos.get(usuario_id, ()))

    def salvar_contato(self, usuario_id: str, contato: ContatoConfianca) -> ContatoConfianca:
        lista = self._contatos.setdefault(usuario_id, [])
        if len(lista) >= LIMITE_CONTATOS:
            raise LimiteAtingido(f"Você pode ter até {LIMITE_CONTATOS} contatos de confiança.")
        novo = replace(contato, id=f"cnt-{next(self._ids)}")
        lista.append(novo)
        return novo

    def remover_contato(self, usuario_id: str, contato_id: str) -> bool:
        lista = self._contatos.get(usuario_id, [])
        restante = [c for c in lista if c.id != contato_id]
        self._contatos[usuario_id] = restante
        return len(restante) != len(lista)


# --- Rotas ---------------------------------------------------------------------------------

router = APIRouter(prefix="/v1/me", tags=["conta"])
_dono = exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)
_NAO_DIGITO = re.compile(r"\D")


def _telefone_valido(v: str) -> str:
    d = _NAO_DIGITO.sub("", v)
    if d.startswith("55") and len(d) in (12, 13):
        d = d[2:]
    if len(d) not in (10, 11):
        raise ValueError("Informe o telefone com DDD.")
    return d


class DadosPessoaisOut(BaseModel):
    nome: str | None
    email: str | None
    cpf_final: str | None = Field(None, description="Últimos 2 dígitos do CPF.")
    telefone: str | None
    data_nascimento: date | None


class DadosPessoaisIn(BaseModel):
    """Só telefone e data de nascimento. Nome: `PATCH /v1/me`. CPF e e-mail não mudam aqui."""

    telefone: str | None = None
    data_nascimento: date | None = None
    remover_telefone: bool = False
    remover_data_nascimento: bool = False

    @field_validator("telefone")
    @classmethod
    def _telefone(cls, v: str | None) -> str | None:
        return None if v is None else _telefone_valido(v)

    @field_validator("data_nascimento")
    @classmethod
    def _nascimento(cls, v: date | None) -> date | None:
        if v is not None and not (date(1900, 1, 1) <= v < date.today()):
            raise ValueError("Data de nascimento inválida.")
        return v


class EnderecoIn(BaseModel):
    apelido: str = Field(min_length=1, max_length=30)
    cep: str
    logradouro: str = Field(min_length=2, max_length=120)
    numero: str = Field(min_length=1, max_length=12)
    complemento: str | None = Field(None, max_length=60)
    bairro: str = Field(min_length=2, max_length=80)
    cidade: str = Field(min_length=2, max_length=80)
    uf: str
    principal: bool = False

    @field_validator("cep")
    @classmethod
    def _cep(cls, v: str) -> str:
        d = _NAO_DIGITO.sub("", v)
        if len(d) != 8:
            raise ValueError("CEP com 8 dígitos.")
        return d

    @field_validator("uf")
    @classmethod
    def _uf(cls, v: str) -> str:
        v = v.strip().upper()
        if not re.fullmatch(r"[A-Z]{2}", v):
            raise ValueError("UF com 2 letras.")
        return v


class EnderecoOut(BaseModel):
    id: str
    apelido: str
    cep: str
    logradouro: str
    numero: str
    complemento: str | None
    bairro: str
    cidade: str
    uf: str
    principal: bool


class FavoritoOut(BaseModel):
    profissional_id: str
    nome: str | None
    nota_publica: float | None
    servicos_concluidos: int | None


class ContatoIn(BaseModel):
    nome: str = Field(min_length=2, max_length=80)
    telefone: str
    parentesco: str | None = Field(None, max_length=40)

    @field_validator("telefone")
    @classmethod
    def _telefone(cls, v: str) -> str:
        return _telefone_valido(v)


class ContatoOut(BaseModel):
    id: str
    nome: str
    telefone: str
    parentesco: str | None


def _conta(contexto: Contexto) -> RepositorioConta:
    return contexto.conta  # type: ignore[no-any-return]


def _limite(erro: LimiteAtingido) -> HTTPException:
    return HTTPException(409, str(erro))


@router.get("/dados-pessoais", response_model=DadosPessoaisOut, summary="Meus dados pessoais")
def ler_dados(
    usuario: Usuario = Depends(_dono), contexto: Contexto = Depends(obter_contexto)
) -> DadosPessoaisOut:
    return DadosPessoaisOut(**vars(_conta(contexto).dados(usuario.id)))


@router.patch(
    "/dados-pessoais", response_model=DadosPessoaisOut, summary="Atualizar telefone e nascimento"
)
def atualizar_dados(
    corpo: DadosPessoaisIn,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> DadosPessoaisOut:
    contexto.usuarios.garantir(usuario.id)
    novo = _conta(contexto).atualizar_dados(
        usuario.id,
        telefone=corpo.telefone,
        data_nascimento=corpo.data_nascimento,
        limpar_telefone=corpo.remover_telefone,
        limpar_nascimento=corpo.remover_data_nascimento,
    )
    return DadosPessoaisOut(**vars(novo))


@router.get("/enderecos", response_model=list[EnderecoOut], summary="Meus endereços salvos")
def listar_enderecos(
    usuario: Usuario = Depends(_dono), contexto: Contexto = Depends(obter_contexto)
) -> list[EnderecoOut]:
    return [EnderecoOut(**vars(e)) for e in _conta(contexto).enderecos(usuario.id)]


@router.post(
    "/enderecos", response_model=EnderecoOut, status_code=201, summary="Salvar um endereço"
)
def criar_endereco(
    corpo: EnderecoIn,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> EnderecoOut:
    contexto.usuarios.garantir(usuario.id)
    try:
        salvo = _conta(contexto).salvar_endereco(usuario.id, Endereco("", **corpo.model_dump()))
    except LimiteAtingido as erro:
        raise _limite(erro) from erro
    return EnderecoOut(**vars(salvo))


@router.put("/enderecos/{endereco_id}", response_model=EnderecoOut, summary="Editar um endereço")
def editar_endereco(
    endereco_id: str,
    corpo: EnderecoIn,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> EnderecoOut:
    repo = _conta(contexto)
    if all(e.id != endereco_id for e in repo.enderecos(usuario.id)):
        raise HTTPException(404, "Endereço não encontrado.")
    salvo = repo.salvar_endereco(usuario.id, Endereco(endereco_id, **corpo.model_dump()))
    return EnderecoOut(**vars(salvo))


@router.delete("/enderecos/{endereco_id}", status_code=204, summary="Remover um endereço")
def remover_endereco(
    endereco_id: str,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    if not _conta(contexto).remover_endereco(usuario.id, endereco_id):
        raise HTTPException(404, "Endereço não encontrado.")
    return Response(status_code=204)


@router.get("/favoritos", response_model=list[FavoritoOut], summary="Profissionais favoritos")
def listar_favoritos(
    usuario: Usuario = Depends(_dono), contexto: Contexto = Depends(obter_contexto)
) -> list[FavoritoOut]:
    return [FavoritoOut(**vars(f)) for f in _conta(contexto).favoritos(usuario.id)]


@router.put("/favoritos/{profissional_id}", status_code=204, summary="Favoritar um profissional")
def favoritar(
    profissional_id: str,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    if profissional_id == usuario.id:
        raise HTTPException(422, "Você não pode favoritar a si mesmo.")
    contexto.usuarios.garantir(usuario.id)
    if not _conta(contexto).favoritar(usuario.id, profissional_id):
        raise HTTPException(404, "Profissional não encontrado.")
    return Response(status_code=204)


@router.delete("/favoritos/{profissional_id}", status_code=204, summary="Tirar dos favoritos")
def desfavoritar(
    profissional_id: str,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    _conta(contexto).desfavoritar(usuario.id, profissional_id)
    return Response(status_code=204)


@router.get(
    "/contatos-confianca", response_model=list[ContatoOut], summary="Meus contatos de confiança"
)
def listar_contatos(
    usuario: Usuario = Depends(_dono), contexto: Contexto = Depends(obter_contexto)
) -> list[ContatoOut]:
    return [ContatoOut(**vars(c)) for c in _conta(contexto).contatos(usuario.id)]


@router.post(
    "/contatos-confianca", response_model=ContatoOut, status_code=201, summary="Adicionar contato"
)
def criar_contato(
    corpo: ContatoIn,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> ContatoOut:
    contexto.usuarios.garantir(usuario.id)
    try:
        salvo = _conta(contexto).salvar_contato(
            usuario.id, ContatoConfianca("", **corpo.model_dump())
        )
    except LimiteAtingido as erro:
        raise _limite(erro) from erro
    return ContatoOut(**vars(salvo))


@router.delete("/contatos-confianca/{contato_id}", status_code=204, summary="Remover contato")
def remover_contato(
    contato_id: str,
    usuario: Usuario = Depends(_dono),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    if not _conta(contexto).remover_contato(usuario.id, contato_id):
        raise HTTPException(404, "Contato não encontrado.")
    return Response(status_code=204)
