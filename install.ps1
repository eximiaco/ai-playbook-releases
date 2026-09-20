# Bootstrap em uma linha do ecossistema AI Playbook (ADR-0005).
#
# Camada fina de download: detecta a arquitetura, baixa o binário ai-setup da
# última release pública (eximiaco/ai-playbook-releases), verifica o sha256
# contra o SHA256SUMS da mesma release e executa o fluxo completo de
# bootstrap (ADR-0004). Toda a lógica vive no binário — este script não
# instala nada por conta própria.
#
# Uso (Windows PowerShell 5.1+ / PowerShell 7+):
#   irm https://raw.githubusercontent.com/eximiaco/ai-playbook-releases/main/install.ps1 | iex
#
# Requisitos: Windows 10/11. Sem privilégios administrativos; idempotente
# (o ai-setup verifica cada passo).

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Base = "https://github.com/eximiaco/ai-playbook-releases/releases/latest/download"

$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch) {
    "AMD64" { $asset = "ai-setup-win32-x64.exe" }
    "ARM64" {
        Write-Host "==> Windows ARM64 detectado: usando o build x64 (roda via emulação)"
        $asset = "ai-setup-win32-x64.exe"
    }
    default { throw "arquitetura não suportada: $arch (esperado AMD64 ou ARM64)" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ai-setup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    Write-Host "==> baixando ai-setup ($asset)"
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/$asset" -OutFile (Join-Path $tmp "ai-setup.exe")
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/SHA256SUMS" -OutFile (Join-Path $tmp "SHA256SUMS")

    Write-Host "==> verificando checksum"
    $match = Select-String -Path (Join-Path $tmp "SHA256SUMS") -Pattern ("\s" + [regex]::Escape($asset) + "$") | Select-Object -First 1
    if (-not $match) { throw "checksum não encontrado para $asset" }
    $expected = $match.Line.Split()[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $tmp "ai-setup.exe")).Hash.ToLower()
    if ($actual -ne $expected) { throw "checksum divergente: esperado $expected, obtido $actual" }

    Write-Host "==> checksum ok; executando ai-setup"
    & (Join-Path $tmp "ai-setup.exe")
    exit $LASTEXITCODE
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
