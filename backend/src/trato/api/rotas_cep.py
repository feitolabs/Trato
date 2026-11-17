"""Rota autenticada para preenchimento automático de endereço a partir do CEP."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field

from trato.api.auth import Usuario
from trato.api.contexto import usuario_atual
from trato.cep import CepIndisponivel, CepNaoEncontrado, ConsultaCep

router = APIRouter(prefix="/v1", tags=["cep"])
_CONSULTA_PADRAO = ConsultaCep()


class CepOut(BaseModel):
    cep: str = Field(description="CEP normalizado com 8 dígitos.")
    logradouro: str = ""
    complemento: str = ""
    bairro: str = ""
    cidade: str
    uf: str = Field(min_length=2, max_length=2)


def _servico(request: Request) -> ConsultaCep:
    personalizado = getattr(request.app.state, "consulta_cep", None)
    return personalizado if isinstance(personalizado, ConsultaCep) else _CONSULTA_PADRAO


@router.get(
    "/cep/{cep}",
    response_model=CepOut,
    summary="Consultar endereço pelo CEP",
    description=(
        "Normaliza o CEP, consulta ViaCEP com fallback BrasilAPI e devolve rua, bairro, "
        "cidade e UF."
    ),
)
def consultar_cep(
    cep: str,
    request: Request,
    _: Usuario = Depends(usuario_atual),
) -> CepOut:
    try:
        resultado = _servico(request).consultar(cep)
    except ValueError as erro:
        raise HTTPException(422, str(erro)) from erro
    except CepNaoEncontrado as erro:
        raise HTTPException(404, str(erro)) from erro
    except CepIndisponivel as erro:
        raise HTTPException(503, str(erro)) from erro
    return CepOut(
        cep=resultado.cep,
        logradouro=resultado.logradouro,
        complemento=resultado.complemento,
        bairro=resultado.bairro,
        cidade=resultado.cidade,
        uf=resultado.uf,
    )
