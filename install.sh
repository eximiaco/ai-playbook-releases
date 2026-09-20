#!/bin/sh
# Bootstrap em uma linha do ecossistema AI Playbook (ADR-0005).
#
# Camada fina de download: detecta a plataforma, baixa o binário ai-setup da
# última release pública (eximiaco/ai-playbook-releases), verifica o sha256
# contra o SHA256SUMS da mesma release e executa o fluxo completo de
# bootstrap (ADR-0004). Toda a lógica de instalação vive no binário — este
# script não instala nada por conta própria.
#
# Uso:
#   curl -fsSL https://github.com/eximiaco/ai-playbook-releases/releases/latest/download/install.sh | sh
#
# Requisitos: POSIX sh, curl, awk, tput (opcional) e um utilitário de sha256
# (shasum ou sha256sum). Sem privilégios administrativos; idempotente (o
# ai-setup verifica cada passo).

set -eu

# ---------------------------------------------------- splash (EximiaCo)
# Porta POSIX sh do splash animado validado em
# scripts/eximia-splash-wordmark.sh: onda de energia atravessando "EXIMIA.CO"
# (fonte pixel compacta, 2 pixels por célula via ▀▄█ → 3 linhas de altura),
# da esquerda para a direita: letras apagadas em Azul 1 → pulso Azul 5 sob a
# onda → assentam com o "X" em Azul 4 e o resto em Cinza 3; varredura de
# gradiente, respiro e tagline. Render por awk sobre um grid pré-computado
# (glifos são constantes) — sem arrays, sem depender de locale.
#
# Antes da animação, limpa a tela (apenas no ramo animado: pipes, NO_COLOR e
# EXIMIA_SPLASH=0 permanecem sem mutação do terminal).
#
# Anima apenas com stdout em terminal e terminal largo (≥ 42 colunas).
# Variáveis: SPEED (multiplicador do ritmo, default 1) · EXIMIA_ANIMATE=1
# (força animação) · EXIMIA_SPLASH=0 (pula a animação) · NO_COLOR (desativa).
splash() {
  sp_cols="$(tput cols 2>/dev/null || echo 80)"
  case "$sp_cols" in ''|*[!0-9]*) sp_cols=80 ;; esac
  sp_animate=0
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then sp_animate=1; fi
  if [ "${EXIMIA_ANIMATE:-}" = "1" ]; then sp_animate=1; fi
  if [ "${EXIMIA_SPLASH:-}" = "0" ] || [ "$sp_cols" -lt 42 ] || [ "$sp_animate" -eq 0 ]; then
    printf 'EXIMIA.CO\nTECNOLOGIA PARA IMPULSIONAR A MUDANÇA\n'
    return 0
  fi

  printf '\033[H\033[2J'
  printf '\033[?25l'
  trap 'printf "\033[?25h\033[0m"' EXIT
  awk -v SPEED="${SPEED:-1}" '
    BEGIN {
      W = 40; X0 = 4; X1 = 6
      # Paleta (Manual de ID Visual EximiaCo 28/07/2025)
      pal[0] = "38;2;23;42;90"; pal[1] = "38;2;32;56;127"; pal[2] = "38;2;49;73;167"
      pal[3] = "38;2;86;136;232"; pal[4] = "38;2;108;187;252"
      wordc = "38;2;216;216;216"; xc = "38;2;86;136;232"; tagc = "38;2;160;160;160"
      rst = "\033[0m"
      # Grid pixel do wordmark (validado contra scripts/eximia-splash-wordmark.sh):
      # 40 colunas × 3 linhas de célula (2 px por célula via ▀▄█).
      # Dígito por célula: 0 vazio · 1 ▀ (pixel de cima) · 2 ▄ (de baixo) · 3 █.
      # Colunas 4–6 = o "X" destacado do logo (Azul 4).
      rows[0] = "3110303013103202301310211120002111021120"
      rows[1] = "3100212003003010300300311130003000030030"
      rows[2] = "1110101011101000101110100010100111001100"
      speed = SPEED + 0

      printf "\n"
      render("wave", 0); tick(0.05)
      for (k = 1; k < W; k++) { printf "\033[3A"; render("wave", k); tick(0.035) }
      for (k = 4; k >= 0; k--) { printf "\033[3A"; render("sweep", k); tick(0.08) }
      printf "\033[3A"; render("settle", 0); tick(0.15)
      printf "\n\033[2m\033[%smTECNOLOGIA PARA IMPULSIONAR A MUDANÇA%s\n\n", tagc, rst
      exit 0
    }
    function tick(d) {
      d = d * speed
      if (d != 0) { fflush(""); system("sleep " d) }
    }
    function render(mode, k,    pr, c, d, style, ch) {
      for (pr = 0; pr < 3; pr++) {
        printf "\033[2K"
        for (c = 0; c < W; c++) {
          d = substr(rows[pr], c + 1, 1)
          if (d == "0") { printf " "; continue }
          if (mode == "wave") {
            if (c < k) style = (c >= X0 && c <= X1) ? xc : wordc
            else if (c == k) style = pal[4]
            else style = pal[0]
          } else if (mode == "sweep") {
            style = pal[(c + k) % 5]
          } else {
            style = (c >= X0 && c <= X1) ? xc : wordc
          }
          ch = (d == "3") ? "█" : (d == "1" ? "▀" : "▄")
          printf "\033[%sm%s%s", style, ch, rst
        }
        printf "\n"
      }
    }
  ' < /dev/null || :
  printf '\033[?25h\033[0m'
}

splash

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
if [ "$status" -eq 0 ]; then
  sp_profile="$HOME/.profile"
  case "${SHELL:-}" in
    */zsh|zsh)   sp_profile="$HOME/.zshrc" ;;
    */fish|fish) sp_profile="$HOME/.config/fish/config.fish" ;;
    "")          sp_profile="$HOME/.profile" ;;
    *)           sp_profile="$HOME/.bashrc" ;;
  esac
  printf '\n==> para carregar o novo PATH: abra uma nova sessão de terminal,\n'
  printf '    ou recarregue o perfil do shell (source %s)\n' "$sp_profile"
fi
exit "$status"
