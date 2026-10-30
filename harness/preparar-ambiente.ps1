# Prepara o ambiente do backend (Windows): cria backend\.venv e instala o backend com extras dev.
# Uso: .\harness\preparar-ambiente.ps1      (precisa de Python 3.11 ou mais novo)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$venv = Join-Path $raiz "backend\.venv"
$venvPy = Join-Path $venv "Scripts\python.exe"

if (-not (Test-Path $venvPy)) {
    $criado = $false
    foreach ($tentativa in @(@("py", "-3.11"), @("py", "-3"), @("python"))) {
        if (-not (Get-Command $tentativa[0] -ErrorAction SilentlyContinue)) { continue }
        $args1 = @($tentativa | Select-Object -Skip 1)
        & $tentativa[0] @args1 -c "import sys; sys.exit(sys.version_info < (3, 11))" 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        & $tentativa[0] @args1 -m venv $venv
        $criado = $true
        break
    }
    if (-not $criado) { throw "Precisa de Python 3.11 ou mais novo (instale de python.org)." }
}
& $venvPy -m pip install --upgrade pip
$backend = Join-Path $raiz "backend"
& $venvPy -m pip install -e "$backend[dev]"
if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar o backend." }
Write-Host "Pronto. Rode: python harness/verificar.py"
