"""Consulta pública de endereço por CEP (ViaCEP com fallback BrasilAPI)."""

from trato.cep.consulta import (
    CepIndisponivel,
    CepNaoEncontrado,
    ConsultaCep,
    EnderecoCep,
    normalizar_cep,
)

__all__ = [
    "CepIndisponivel",
    "CepNaoEncontrado",
    "ConsultaCep",
    "EnderecoCep",
    "normalizar_cep",
]
