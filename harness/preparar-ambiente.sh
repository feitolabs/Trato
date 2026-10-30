#!/usr/bin/env bash
# Prepara o ambiente do backend (macOS/Linux/Git Bash): cria backend/.venv e instala o backend com extras dev.
# Uso: ./harness/preparar-ambiente.sh      (variável PYTHON escolhe o interpretador; precisa ser 3.11+)
set -euo pipefail
raiz="$(cd "$(dirname "$0")/.." && pwd)"
py="${PYTHON:-}"
if [ -z "$py" ]; then
  for c in python3.12 python3.11 python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then py="$c"; break; fi
  done
fi
[ -n "$py" ] || { echo "FALHA: precisa de Python 3.11 ou mais novo (defina PYTHON=/caminho/python)"; exit 1; }
echo "Usando: $($py --version) ($py)"
[ -d "$raiz/backend/.venv" ] || "$py" -m venv "$raiz/backend/.venv"
venv_py="$raiz/backend/.venv/bin/python"
[ -x "$venv_py" ] || venv_py="$raiz/backend/.venv/Scripts/python.exe"
"$venv_py" -m pip install --upgrade pip
"$venv_py" -m pip install -e "$raiz/backend[dev]"
echo "Pronto. Rode: python harness/verificar.py"
