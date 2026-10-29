"""Verificação automática do Trato: segredos, backend (lint + testes) e app Flutter.

Uso: python harness/verificar.py [--etapa segredos|backend|app]   (ou harness/verificar.ps1 / harness/verificar.sh)
Sai com código 1 se qualquer etapa falhar.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
BACKEND = RAIZ / "backend"
APP = RAIZ / "app"
ADMIN = RAIZ / "admin"
PROJETOS_FLUTTER = (APP, ADMIN)

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


def _arquivos_dart() -> list[Path]:
    """Dart de lib/ do app e do painel admin (build/ e .dart_tool/ ficam de fora)."""
    return [a for pasta in PROJETOS_FLUTTER if (pasta / "lib").is_dir() for a in (pasta / "lib").rglob("*.dart")]


def checar_cores_soltas() -> bool:
    """Regra 7: cor só no tema. Color(0x...) e Colors.* fora de app/lib/tema/ falham."""
    titulo("App e painel — cores fora do tema")
    padrao = re.compile(r"\bColor\(\s*0x|\bColor\.fromARGB\(|\bColor\.fromRGBO\(|\bColors\.(?!transparent\b)")
    ok = True
    for arquivo in _arquivos_dart():
        if arquivo.parent.name == "tema" or "tema" in arquivo.relative_to(RAIZ).parts[:-1]:
            continue
        for numero, linha in enumerate(arquivo.read_text(encoding="utf-8").splitlines(), start=1):
            if padrao.search(linha):
                print(f"FALHA: cor solta em {arquivo.relative_to(RAIZ)}:{numero} — use CoresTrato")
                ok = False
    if ok:
        print("ok")
    return ok


# Textos proibidos pela decisão D13 (Auditoria V2). Só valem em texto de tela: comentários ficam livres.
TEXTOS_PROIBIDOS = re.compile(
    r"(?i)escrow|garantia total|profissional seguro|reembolso autom[aá]tico"
    r"|menor taxa do mercado|atendimento 24\s*/\s*7|24\s*/\s*7|24 horas por dia"
)


def checar_textos_proibidos() -> bool:
    """D13: o app não pode exibir promessas proibidas. Comentários (//) são ignorados;
    `verificar: ignorar` na linha libera um caso justificado."""
    titulo("App e painel — textos proibidos (D13)")
    ok = True
    for arquivo in _arquivos_dart():
        for numero, linha in enumerate(arquivo.read_text(encoding="utf-8").splitlines(), start=1):
            codigo = linha.split("//", 1)[0] if linha.lstrip().startswith("//") else linha
            if linha.lstrip().startswith("//") or "verificar: ignorar" in linha:
                continue
            if TEXTOS_PROIBIDOS.search(codigo):
                print(f"FALHA: texto proibido (D13) em {arquivo.relative_to(RAIZ)}:{numero}")
                ok = False
    if ok:
        print("ok")
    return ok


def python_do_backend() -> str:
    """Python do backend: $TRATO_PYTHON, backend/.venv, .venv da raiz ou o python que roda este script."""
    if (env := os.environ.get("TRATO_PYTHON")) and Path(env).exists():
        return env
    sub = "Scripts/python.exe" if sys.platform == "win32" else "bin/python"
    for venv in (BACKEND / ".venv", RAIZ / ".venv"):
        if (venv / sub).exists():
            return str(venv / sub)
    return sys.executable


def faltam_modulos(py: str, modulos: list[str]) -> list[str]:
    """Módulos que o python do backend não consegue importar."""
    faltam = []
    for modulo in modulos:
        achou = subprocess.run([py, "-c", f"import {modulo}"], capture_output=True)
        if achou.returncode != 0:
            faltam.append(modulo)
    return faltam


def rodar(passo: str, comando: list[str], pasta: Path) -> bool:
    titulo(passo)
    resultado = subprocess.run(comando, cwd=pasta)
    if resultado.returncode != 0:
        print(f"FALHA: {passo}")
        return False
    return True


def checar_backend() -> bool:
    py = python_do_backend()
    # fastapi/psycopg/jwt: dependências de execução; ruff/pytest/httpx: extras `dev`.
    if faltam := faltam_modulos(py, ["ruff", "pytest", "httpx", "fastapi", "psycopg", "jwt"]):
        titulo("Backend — ambiente")
        print(f"FALHA: python usado: {py}")
        print(f"FALHA: faltam no ambiente: {', '.join(faltam)}")
        print("Prepare o ambiente uma vez (cria backend/.venv e instala tudo):")
        print(r"  Windows:       .\harness\preparar-ambiente.ps1")
        print("  macOS/Linux:   ./harness/preparar-ambiente.sh")
        return False
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


def checar_flutter(nome: str, pasta: Path) -> bool:
    flutter = achar_flutter()
    if not flutter:
        titulo(nome)
        print(f"AVISO: Flutter SDK não instalado — análise e testes de {nome} foram pulados.")
        return True
    if not pasta.is_dir():
        return True
    ok = rodar(f"{nome} — dependências", [flutter, "pub", "get"], pasta)
    ok = rodar(f"{nome} — análise (flutter analyze)", [flutter, "analyze"], pasta) and ok
    ok = rodar(f"{nome} — testes (flutter test)", [flutter, "test"], pasta) and ok
    return ok


def checar_admin() -> bool:
    return checar_flutter("Painel admin", ADMIN)


ETAPAS = {
    "segredos": [checar_segredos, checar_env_ignorado],
    "backend": [checar_backend],
    "app": [checar_cores_soltas, checar_textos_proibidos, checar_app, checar_admin],
}


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Verificação do Trato.")
    parser.add_argument(
        "--etapa",
        choices=["todas", *ETAPAS],
        default="todas",
        help="roda só um grupo de checagens (o CI usa um job por grupo); padrão: todas",
    )
    escolha = parser.parse_args().etapa
    grupos = list(ETAPAS) if escolha == "todas" else [escolha]
    resultados = [checar() for grupo in grupos for checar in ETAPAS[grupo]]
    titulo("Resultado")
    if all(resultados):
        print("TUDO OK")
        return 0
    print("VERIFICAÇÃO FALHOU")
    return 1


if __name__ == "__main__":
    sys.exit(main())
