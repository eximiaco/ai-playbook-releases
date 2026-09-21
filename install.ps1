# Bootstrap em uma linha do ecossistema AI Playbook (ADR-0005).
#
# Camada fina de download: detecta a arquitetura, baixa o binario ai-setup da
# ultima release publica (eximiaco/ai-playbook-releases), verifica o sha256
# contra o SHA256SUMS da mesma release e executa o fluxo completo de
# bootstrap (ADR-0004). Toda a logica vive no binario - este script nao
# instala nada por conta propria.
#
# Uso (Windows PowerShell 5.1+ / PowerShell 7+):
#   irm https://raw.githubusercontent.com/eximiaco/ai-playbook-releases/main/install.ps1 | iex
#
# Requisitos: Windows 10/11. Sem privilegios administrativos; idempotente
# (o ai-setup verifica cada passo).
#
# Este arquivo e ASCII-only e NAO tem BOM de proposito (ver ADR-0005):
# - Com BOM, `irm <raw> | iex` quebra no PowerShell 5.1: o tokenizer nao
#   trata '#' depois do BOM (U+FEFF) como comentario e tenta executar
#   tokens da primeira linha como comando (ex.: "ADR-0005 is not
#   recognized"). O erro e non-terminating e o script segue, mas o ruido
#   confunde o usuario.
# - Ja sem BOM, o PowerShell 5.1 le o arquivo por caminho como ANSI; manter
#   o conteudo ASCII-only garante parse e mensagens corretos nas duas formas
#   de execucao (pipe para iex e arquivo baixado).

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Base = "https://github.com/eximiaco/ai-playbook-releases/releases/latest/download"

$arch = $env:PROCESSOR_ARCHITECTURE
switch ($arch) {
    "AMD64" { $asset = "ai-setup-win32-x64.exe" }
    "ARM64" {
        Write-Host "==> Windows ARM64 detectado: usando o build x64 (roda via emulacao)"
        $asset = "ai-setup-win32-x64.exe"
    }
    default { throw "arquitetura nao suportada: $arch (esperado AMD64 ou ARM64)" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("ai-setup-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    Write-Host "==> baixando ai-setup ($asset)"
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/$asset" -OutFile (Join-Path $tmp "ai-setup.exe")
    Invoke-WebRequest -UseBasicParsing -Uri "$Base/SHA256SUMS" -OutFile (Join-Path $tmp "SHA256SUMS")

    Write-Host "==> verificando checksum"
    $match = Select-String -Path (Join-Path $tmp "SHA256SUMS") -Pattern ("\s" + [regex]::Escape($asset) + "$") | Select-Object -First 1
    if (-not $match) { throw "checksum nao encontrado para $asset" }
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