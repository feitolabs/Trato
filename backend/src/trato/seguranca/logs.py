"""Logs sem dado pessoal: toda mensagem de log passa por `redigir` antes de sair.

Troca e-mail, CPF, telefone, token (Bearer/JWT) e parâmetros sensíveis de query por marcas.
Instalado na fábrica de registros do `logging`, vale para qualquer logger e handler (inclusive o
de acesso do uvicorn). É uma rede de proteção: o certo é não logar dado pessoal.
"""

from __future__ import annotations

import logging
import re

_PADROES: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*"), "[jwt]"),
    (re.compile(r"(?i)\bbearer\s+[\w.~+/=-]+"), "Bearer [token]"),
    (
        re.compile(
            r"(?i)([?&](?:token|access_token|apikey|api_key|key|senha|password|cpf|telefone|"
            r"phone|email|codigo|code)=)[^&\s\"']*"
        ),
        r"\1[oculto]",
    ),
    (re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"), "[email]"),
    (re.compile(r"\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b"), "[cpf]"),
    (
        re.compile(r"(?<![\w-])(?:\+?\d{2}[\s.-]?)?\(?\d{2}\)?[\s.-]?9?\d{4}[\s.-]?\d{4}(?![\w-])"),
        "[telefone]",
    ),
)


def redigir(texto: str) -> str:
    for padrao, troca in _PADROES:
        texto = padrao.sub(troca, texto)
    return texto


_instalado = False


def instalar_filtro_logs() -> None:
    """Idempotente: embrulha a fábrica de registros uma única vez."""
    global _instalado
    if _instalado:
        return
    fabrica = logging.getLogRecordFactory()

    def nova_fabrica(*args, **kwargs) -> logging.LogRecord:  # type: ignore[no-untyped-def]
        registro = fabrica(*args, **kwargs)
        try:
            registro.msg = redigir(registro.getMessage())
            registro.args = ()
        except Exception:  # noqa: BLE001, S110 - log nunca derruba o programa
            pass
        return registro

    logging.setLogRecordFactory(nova_fabrica)
    _instalado = True
