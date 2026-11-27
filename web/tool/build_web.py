"""Compila o site para publicar, sempre com a configuração.

Uso (dentro de web/): python tool/build_web.py [arquivo.json]

Cada valor vem da variável de ambiente de mesmo nome ou, na falta dela, do arquivo JSON
(padrão: dart-defines.json, ignorado pelo git). Falha se faltar algum. Só imprime nomes.
No fim grava o hash do main.dart.js; o buildCommand do vercel.json confere esse hash e
recusa publicar um build feito por outro caminho (por exemplo, sem configuração).
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

WEB = Path(__file__).resolve().parent.parent
SAIDA = WEB / "build" / "web"
SELO = SAIDA / "trato-config.sha256"
NOMES = ("TRATO_API_URL", "SUPABASE_URL", "SUPABASE_ANON_KEY")


def papel_do_jwt(valor: str) -> str:
    partes = valor.split(".")
    if len(partes) != 3:
        return ""
    try:
        corpo = base64.urlsafe_b64decode(partes[1] + "=" * (-len(partes[1]) % 4))
        return str(json.loads(corpo).get("role", ""))
    except (ValueError, AttributeError):
        return ""


def problemas(valores: dict[str, str]) -> list[str]:
    """Mesmas regras de lib/dados/config_web.dart."""
    erros = []
    for nome in ("TRATO_API_URL", "SUPABASE_URL"):
        url = urlparse(valores[nome])
        local = url.scheme == "http" and url.hostname in ("localhost", "127.0.0.1")
        if not url.hostname or not (url.scheme == "https" or local):
            erros.append(f"{nome} ausente ou inválida")
    chave = valores["SUPABASE_ANON_KEY"]
    if not chave:
        erros.append("SUPABASE_ANON_KEY ausente")
    elif chave.startswith(("sb_secret_", "sk_", "rk_")) or papel_do_jwt(chave) == "service_role":
        erros.append("SUPABASE_ANON_KEY é uma chave secreta: use só a pública")
    return erros


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    # O selo antigo sai antes de tudo: se algo falhar, nada fica liberado para publicar.
    SELO.unlink(missing_ok=True)

    arquivo = Path(sys.argv[1]) if len(sys.argv) > 1 else WEB / "dart-defines.json"
    if len(sys.argv) > 1 and not arquivo.is_file():
        print(f"FALHA: arquivo não encontrado: {arquivo}")
        return 1
    do_arquivo = json.loads(arquivo.read_text(encoding="utf-8-sig")) if arquivo.is_file() else {}
    valores = {n: str(os.environ.get(n) or do_arquivo.get(n) or "").strip() for n in NOMES}
    if erros := problemas(valores):
        for erro in erros:
            print(f"FALHA: {erro}")
        return 1

    flutter = shutil.which("flutter")
    if not flutter:
        print("FALHA: flutter não está no PATH")
        return 1
    # Só os três nomes públicos vão para o compilador, mesmo que o arquivo de origem tenha outros.
    with tempfile.TemporaryDirectory() as pasta:
        defines = Path(pasta) / "defines.json"
        defines.write_text(json.dumps(valores), encoding="utf-8")
        comando = [flutter, "build", "web", "--release", f"--dart-define-from-file={defines}"]
        if (codigo := subprocess.run(comando, cwd=WEB).returncode) != 0:
            return codigo

    resumo = hashlib.sha256((SAIDA / "main.dart.js").read_bytes()).hexdigest()
    # Caminho relativo a web/ e fim de linha LF: é o que o `sha256sum -c` da Vercel (Linux) espera.
    SELO.write_bytes(f"{resumo}  build/web/main.dart.js\n".encode("ascii"))
    print("ok: build/web pronto para publicar, com configuração")
    return 0


if __name__ == "__main__":
    sys.exit(main())
