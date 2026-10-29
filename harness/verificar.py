"""Verificação automática do Trato: segredos, backend (lint + testes) e app Flutter.

Uso: python harness/verificar.py   (ou harness/verificar.ps1 / harness/verificar.sh)
Sai com código 1 se qualquer etapa falhar.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BACKEND = RAIZ / "backend"
APP = RAIZ / "app"

# Padrões de segredo. Nomes de variáveis sozinhos (ex.: STRIPE_SECRET_KEY=) não disparam.
PADROES_SEGREDO = {
    "chave Stripe": re.compile(r"\b(sk|rk|pk)_(live|test)_[0-9A-Za-z]{10,}"),
    "webhook Stripe": re.compile(r"\bwhsec_[0-9A-Za-z]{10,}"),
    "JWT (chave Supabase)": re.compile(r"\beyJ[0-9A-Za-z_-]{10,}\.eyJ[0-9A-Za-z_-]{10,}\.[0-9A-Za-z_-]{10,}"),
    "token GitHub": re.compile(r"\b(ghp|gho|ghs|ghu|github_pat)_[0-9A-Za-z_]{20,}"),
    "chave privada": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "chave AWS": re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    "URL com senha": re.compile(r"[a-z]+://[^\s:/@]+:[^\s@/]{6,}@"),
    "senha atribuída": re.compile(
        r"(?i)\b(password|senha|secret|api_key|apikey|token)\b\s*[:=]\s*['\"][^'\"\s]{6,}['\"]"
    ),
}
EXTENSOES_BINARIAS = {".pdf", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".ttf", ".otf", ".woff", ".woff2"}


def titulo(texto: str) -> None:
    print(f"\n== {texto} ==", flush=True)


def arquivos_do_projeto() -> list[Path]:
    """Arquivos versionados ou novos, respeitando o .gitignore."""
    saida = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=RAIZ, capture_output=True, check=True,
    ).stdout.decode("utf-8")
    return [RAIZ / p for p in saida.split("\0") if p]


def checar_segredos() -> bool:
    titulo("Segredos")
    ok = True
    for arquivo in arquivos_do_projeto():
        if arquivo.suffix.lower() in EXTENSOES_BINARIAS or not arquivo.is_file():
            continue
        if arquivo.name == ".env" or (arquivo.name.startswith(".env.") and arquivo.name != ".env.example"):
            print(f"FALHA: {arquivo.relative_to(RAIZ)} não pode ser versionado")
            ok = False
            continue
        texto = arquivo.read_text(encoding="utf-8", errors="ignore")
        for numero, linha in enumerate(texto.splitlines(), start=1):
            if "verificar: ignorar" in linha:
                continue
            for nome, padrao in PADROES_SEGREDO.items():
                if padrao.search(linha):
                    print(f"FALHA: possível {nome} em {arquivo.relative_to(RAIZ)}:{numero}")
                    ok = False
    if ok:
        print("ok — nenhum segredo encontrado")
    return ok


def checar_env_ignorado() -> bool:
    titulo(".env ignorado pelo git")
    resultado = subprocess.run(["git", "check-ignore", "-q", ".env"], cwd=RAIZ)
    if resultado.returncode == 0:
        print("ok")
        return True
    print("FALHA: .env não está no .gitignore")
    return False


def python_do_backend() -> str:
    venv = BACKEND / ".venv" / ("Scripts/python.exe" if sys.platform == "win32" else "bin/python")
    return str(venv) if venv.exists() else sys.executable


def rodar(passo: str, comando: list[str], pasta: Path) -> bool:
    titulo(passo)
    resultado = subprocess.run(comando, cwd=pasta)
    if resultado.returncode != 0:
        print(f"FALHA: {passo}")
        return False
    return True


def checar_backend() -> bool:
    py = python_do_backend()
    ok = rodar("Backend — lint (ruff)", [py, "-m", "ruff", "check", "."], BACKEND)
    ok = rodar("Backend — formatação (ruff)", [py, "-m", "ruff", "format", "--check", "."], BACKEND) and ok
    ok = rodar("Backend — testes (pytest)", [py, "-m", "pytest", "-q"], BACKEND) and ok
    return ok


def achar_flutter() -> str | None:
    """Flutter no PATH, em $FLUTTER_ROOT ou na instalação padrão C:\\flutter."""
    if achado := shutil.which("flutter"):
        return achado
    nome = "flutter.bat" if sys.platform == "win32" else "flutter"
    for raiz in (os.environ.get("FLUTTER_ROOT"), "C:/flutter"):
        if raiz and (Path(raiz) / "bin" / nome).exists():
            return str(Path(raiz) / "bin" / nome)
    return None


def checar_app() -> bool:
    flutter = achar_flutter()
    if not flutter:
        titulo("App Flutter")
        print("AVISO: Flutter SDK não instalado — análise e testes do app foram pulados.")
        return True
    ok = rodar("App — dependências", [flutter, "pub", "get"], APP)
    ok = rodar("App — análise (flutter analyze)", [flutter, "analyze"], APP) and ok
    ok = rodar("App — testes (flutter test)", [flutter, "test"], APP) and ok
    return ok


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    resultados = [checar_segredos(), checar_env_ignorado(), checar_backend(), checar_app()]
    titulo("Resultado")
    if all(resultados):
        print("TUDO OK")
        return 0
    print("VERIFICAÇÃO FALHOU")
    return 1


if __name__ == "__main__":
    sys.exit(main())
