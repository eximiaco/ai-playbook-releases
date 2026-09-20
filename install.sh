#!/bin/sh
# Bootstrap em uma linha do ecossistema AI Playbook (ADR-0005).
#
# Camada fina de download: detecta a plataforma, baixa o binário ai-setup da
# última release pública (eximiaco/ai-playbook-releases), verifica o sha256
# contra o SHA256SUMS da mesma release e executa o fluxo completo de
# bootstrap (ADR-0004). Toda a lógica vive no binário — este script não
# instala nada por conta própria.
#
# Uso:
#   curl -fsSL https://github.com/eximiaco/ai-playbook-releases/releases/latest/download/install.sh | sh
#
# Requisitos: POSIX sh, curl e um utilitário de sha256 (shasum ou sha256sum).
# Sem privilégios administrativos; idempotente (o ai-setup verifica cada passo).

set -eu

REPO="eximiaco/ai-playbook-releases"
BASE="https://github.com/${REPO}/releases/latest/download"

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *)
    printf 'erro: sistema operacional não suportado: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x64 ;;
  *)
    printf 'erro: arquitetura não suportada: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

if [ "${os}" = "linux" ] && [ "${arch}" = "arm64" ]; then
  printf 'erro: o ai-setup ainda não publica build para linux-arm64\n' >&2
  printf '      use uma máquina linux-x64 ou baixe o binário manualmente\n' >&2
  exit 1
fi

asset="ai-setup-${os}-${arch}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf '==> baixando ai-setup (%s)\n' "$asset"
curl -fsSL "${BASE}/${asset}" -o "${tmp}/ai-setup"
curl -fsSL "${BASE}/SHA256SUMS" -o "${tmp}/SHA256SUMS"

printf '==> verificando checksum\n'
expected="$(awk -v a="${asset}" '$2 == a { print $1 }' "${tmp}/SHA256SUMS")"
if [ -z "$expected" ]; then
  printf 'erro: checksum não encontrado para %s\n' "$asset" >&2
  exit 1
fi

if command -v shasum >/dev/null 2>&1; then
  actual="$(shasum -a 256 "${tmp}/ai-setup" | awk '{ print $1 }')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${tmp}/ai-setup" | awk '{ print $1 }')"
else
  printf 'erro: nenhum utilitário de sha256 disponível (instale shasum ou sha256sum)\n' >&2
  exit 1
fi

if [ "$actual" != "$expected" ]; then
  printf 'erro: checksum divergente para %s (esperado %s, obtido %s)\n' "$asset" "$expected" "$actual" >&2
  exit 1
fi

chmod +x "${tmp}/ai-setup"
printf '==> checksum ok; executando ai-setup\n'
status=0
"${tmp}/ai-setup" || status=$?
exit "$status"
