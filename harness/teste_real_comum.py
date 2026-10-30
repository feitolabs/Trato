"""Base dos scripts `teste_real_*.py` (só biblioteca padrão; sem criar conta, sem escrever dado).

Todos exigem `TRATO_TESTE_REAL=sim` e leem as chaves do ambiente (nunca de argumento nem de arquivo).
Saída: uma linha `OK` ou `FALHOU` por verificação; código de saída 1 se alguma falhar, 2 se faltar
configuração. Se faltar uma variável opcional, a verificação sai como `PULADO` (não conta como falha).
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

_resultados: list[tuple[str, str]] = []

if hasattr(sys.stdout, "reconfigure"):  # console do Windows (cp1252) não imprime setas e acentos
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def exigir_teste_real() -> None:
    if os.environ.get("TRATO_TESTE_REAL") != "sim":
        print("Este script fala com serviços reais. Defina TRATO_TESTE_REAL=sim para rodar.")
        sys.exit(2)


def variavel(nome: str, obrigatoria: bool = True) -> str | None:
    valor = os.environ.get(nome, "").strip()
    if not valor and obrigatoria:
        print(f"Falta a variável de ambiente {nome}. Veja docs/roteiro-testes-reais.md.")
        sys.exit(2)
    return valor or None


def registra(nome: str, ok: bool | None, detalhe: str = "") -> None:
    estado = "PULADO" if ok is None else ("OK" if ok else "FALHOU")
    _resultados.append((nome, estado))
    print(f"{estado:7} {nome}" + (f"  [{detalhe}]" if detalhe and estado != "OK" else ""))


def http(
    metodo: str, url: str, cabecalhos: dict[str, str] | None = None, corpo: bytes | None = None
) -> tuple[int, bytes]:
    pedido = urllib.request.Request(url, data=corpo, method=metodo, headers=cabecalhos or {})  # noqa: S310
    try:
        with urllib.request.urlopen(pedido, timeout=30) as resposta:  # noqa: S310
            return resposta.status, resposta.read()
    except urllib.error.HTTPError as erro:
        return erro.code, erro.read()


def json_de(dados: bytes):
    try:
        return json.loads(dados)
    except ValueError:
        return None


def encerrar() -> None:
    falhas = [n for n, e in _resultados if e == "FALHOU"]
    pulados = [n for n, e in _resultados if e == "PULADO"]
    print(f"\nResumo: {len(_resultados) - len(falhas) - len(pulados)} OK, {len(falhas)} FALHOU, {len(pulados)} PULADO")
    sys.exit(1 if falhas else 0)
