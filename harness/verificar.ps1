# Verificação do Trato (Windows). Uso: .\harness\verificar.ps1
$raiz = Split-Path -Parent $PSScriptRoot
$py = Join-Path $raiz "backend\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
& $py (Join-Path $PSScriptRoot "verificar.py")
exit $LASTEXITCODE
