"""Verificador de `--dart-define` (revisão M14): nada de segredo dentro do app ou do painel.

Tudo que entra por `--dart-define` vira constante do APK/IPA/JS e pode ser extraído. Este script
falha se algum arquivo do projeto referenciar:
  - `--dart-define-from-file=` apontando para um `.env` (o da raiz tem service_role, DATABASE_URL...);
  - um arquivo de dart-define (json/env) que exista e tenha chave fora da lista permitida
    ou com nome de segredo;
  - `--dart-define=NOME=...` com nome fora da lista permitida.
Só nomes aparecem na saída, nunca valores.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Mantenha igual a app/lib/dados/defines_publicos.dart e admin/lib/dados/defines_publicos.dart.
PERMITIDAS = {
    "TRATO_MODO", "TRATO_API_URL", "SUPABASE_URL", "SUPABASE_ANON_KEY",
    "GOOGLE_WEB_CLIENT_ID", "GOOGLE_IOS_CLIENT_ID", "GALERIA",
    "ADMIN_MODO", "ADMIN_API_URL", "ADMIN_SUPABASE_URL", "ADMIN_SUPABASE_ANON_KEY",
}
NOME_SEGREDO = re.compile(r"(?i)service_role|secret|database_url|db_url|^sk_|private_key|jwt_secret")
VALOR_SEGREDO = re.compile(r"\b(sk|rk)_(live|test)_[0-9A-Za-z]{6,}|\bwhsec_[0-9A-Za-z]{6,}")

REF_ARQUIVO = re.compile(r"""--dart-define-from-file[=\s]+([^\s"'`)]+)""")
REF_DEFINE = re.compile(r"--dart-define[=\s]+([A-Za-z_][A-Za-z0-9_]*)=")
EXTENSOES_TEXTO = {".md", ".txt", ".yml", ".yaml", ".sh", ".ps1", ".json", ".py", ".bat", ".cmd", ".toml"}
# Documentos que citam o padrão proibido de propósito (relatório e este verificador).
IGNORAR = {"docs/revisao-seguranca.md", "docs/fix-app.md", "harness/verificar_defines.py", "harness/PROGRESSO.md"}


def nome_proibido(nome: str) -> bool:
    return nome not in PERMITIDAS or bool(NOME_SEGREDO.search(nome))


def chaves_do_arquivo(caminho: Path) -> list[str]:
    texto = caminho.read_text(encoding="utf-8", errors="replace")
    if caminho.suffix == ".json":
        try:
            dados = json.loads(texto)
            return list(dados) if isinstance(dados, dict) else []
        except json.JSONDecodeError:
            return []
    return [m.group(1) for m in re.finditer(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=", texto, re.M)]


def checar_arquivo_define(ref: str, origem: str, base: Path) -> list[str]:
    erros: list[str] = []
    nome = Path(ref).name.lower()
    if nome == ".env" or (nome.startswith(".env") and nome != ".env.example"):
        erros.append(f"{origem}: --dart-define-from-file aponta para '{ref}' (use um arquivo só com as variáveis públicas)")
    for candidato in {(base / ref), (RAIZ / ref)}:
        if candidato.is_file():
            for chave in chaves_do_arquivo(candidato):
                if nome_proibido(chave):
                    erros.append(f"{origem}: '{ref}' tem a chave proibida {chave}")
            if VALOR_SEGREDO.search(candidato.read_text(encoding="utf-8", errors="replace")):
                erros.append(f"{origem}: '{ref}' tem valor com cara de segredo (sk_/whsec_)")
            break
    return erros


def checar_texto(texto: str, origem: str, base: Path) -> list[str]:
    erros: list[str] = []
    for m in REF_ARQUIVO.finditer(texto):
        erros += checar_arquivo_define(m.group(1), origem, base)
    for m in REF_DEFINE.finditer(texto):
        if nome_proibido(m.group(1)):
            erros.append(f"{origem}: --dart-define com o nome proibido {m.group(1)}")
    return erros


def arquivos() -> list[Path]:
    saida = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=RAIZ, capture_output=True, check=True
    ).stdout.decode("utf-8")
    return [RAIZ / p for p in saida.split("\0") if p]


def verificar() -> list[str]:
    erros: list[str] = []
    for arq in arquivos():
        rel = arq.relative_to(RAIZ).as_posix()
        if rel in IGNORAR or arq.suffix not in EXTENSOES_TEXTO and arq.name != "Makefile":
            continue
        try:
            texto = arq.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        erros += checar_texto(texto, rel, arq.parent)
    return erros


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    print("\n== dart-define: só variáveis públicas ==")
    erros = verificar()
    for e in erros:
        print(f"FALHA: {e}")
    if not erros:
        print("ok")
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main())
