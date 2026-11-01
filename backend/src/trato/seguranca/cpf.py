"""CPF: normalização e conferência dos dois dígitos verificadores.

O banco guarda só os 11 números; a formatação (`000.000.000-00`) é da tela. Um CPF com todos os
dígitos iguais (000... , 111...) passa na conta dos verificadores, mas não existe de verdade.
"""

from __future__ import annotations

import re


def normalizar_cpf(valor: str) -> str:
    """Só os números: `123.456.789-09` vira `12345678909`."""
    return re.sub(r"\D", "", valor or "")


def cpf_valido(valor: str) -> bool:
    """Confere tamanho, repetição e os dois dígitos verificadores."""
    cpf = normalizar_cpf(valor)
    if len(cpf) != 11 or len(set(cpf)) == 1:
        return False
    for posicao in (9, 10):
        soma = sum(int(cpf[n]) * ((posicao + 1) - n) for n in range(posicao))
        digito = (soma * 10) % 11
        if digito == 10:
            digito = 0
        if digito != int(cpf[posicao]):
            return False
    return True
