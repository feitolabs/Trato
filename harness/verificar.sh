#!/usr/bin/env bash
# Verificação do Trato (macOS/Linux/Git Bash). Uso: ./harness/verificar.sh
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
py="$raiz/backend/.venv/bin/python"
[ -x "$py" ] || py="$raiz/backend/.venv/Scripts/python.exe"
[ -x "$py" ] || py="python3"
exec "$py" "$raiz/harness/verificar.py"
