"""CPF: normalização e dígitos verificadores (um CPF, uma conta)."""

from __future__ import annotations

import pytest

from trato.seguranca.cpf import cpf_valido, normalizar_cpf

VALIDOS = ("123.456.789-09", "12345678909", "529.982.247-25")
INVALIDOS = (
    "123.456.789-01",
    "12345678900",
    "111.111.111-11",
    "00000000000",
    "1234567890",
    "123456789091",
    "abc",
    "",
)


@pytest.mark.parametrize("cpf", VALIDOS)
def test_cpf_valido_aceita_formatos_e_so_digitos(cpf: str) -> None:
    assert cpf_valido(cpf)
    assert normalizar_cpf(cpf) == "".join(c for c in cpf if c.isdigit())


@pytest.mark.parametrize("cpf", INVALIDOS)
def test_cpf_valido_recusa_verificador_repeticao_e_tamanho(cpf: str) -> None:
    assert not cpf_valido(cpf)
