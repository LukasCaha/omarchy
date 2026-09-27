#!/usr/bin/env bash
# Omarchy bootstrap. Design only: this run changes nothing.
# curl -fsSL https://raw.githubusercontent.com/LukasCaha/omarchy/main/bootstrap.sh | sh
set -uo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_OFF=$'\033[0m'
  C_INFO=$'\033[44;30m'
  USE_COLOR=1
else
  C_CYAN= C_GREEN= C_RED= C_DIM= C_BOLD= C_OFF= C_INFO=
  USE_COLOR=0
fi

cleanup() { printf '%s\033[?25h' "$C_OFF"; }
trap cleanup EXIT INT TERM

# Same gradient sets as `laravel new`. One is picked per run.
GRADIENTS=(
  "196 160 124 88 52 88"
  "250 248 245 243 240 238"
  "81 75 69 63 57 21"
  "213 177 141 105 69 39"
  "214 208 202 196 160 124"
  "51 50 49 48 47 41"
  "227 221 215 209 203 197"
  "201 165 129 93 57 21"
)

LOGO=(
  " ██████╗  ███╗   ███╗  █████╗  ██████╗   ██████╗  ██╗  ██╗ ██╗   ██╗"
  "██╔═══██╗ ████╗ ████║ ██╔══██╗ ██╔══██╗ ██╔════╝  ██║  ██║ ╚██╗ ██╔╝"
  "██║   ██║ ██╔████╔██║ ███████║ ██████╔╝ ██║       ███████║  ╚████╔╝ "
  "██║   ██║ ██║╚██╔╝██║ ██╔══██║ ██╔══██╗ ██║       ██╔══██║   ╚██╔╝  "
  "╚██████╔╝ ██║ ╚═╝ ██║ ██║  ██║ ██║  ██║ ╚██████╗  ██║  ██║    ██║   "
  " ╚═════╝  ╚═╝     ╚═╝ ╚═╝  ╚═╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═╝    ╚═╝   "
)

header() {
  printf '\n'
  local colors i color
  colors="${GRADIENTS[$((RANDOM % ${#GRADIENTS[@]}))]}"
  read -r -a picked <<<"$colors"
  for i in "${!LOGO[@]}"; do
    if (( USE_COLOR )); then
      color="${picked[$i]}"
      printf '\033[38;5;%sm%s%s\n' "$color" "${LOGO[$i]}" "$C_OFF"
    else
      printf '%s\n' "${LOGO[$i]}"
    fi
  done
  printf '\n'
  printf ' %s INFO %s Preview. This script changes nothing yet.\n\n' "${C_INFO}${C_BOLD}" "$C_OFF"
}

# task LABEL FN [DETAIL...]
# FN is the future work. Today every FN is a no-op.
task() {
  local label="$1" fn="$2"
  shift 2
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i ok=0

  if (( USE_COLOR )); then
    printf '\033[?25l'
    for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
      printf '\r\033[2K %s%s%s %s' "$C_CYAN" "${frames[$((i % 10))]}" "$C_OFF" "$label"
      sleep 0.05
    done
    printf '\033[?25h'
  fi

  if "$fn"; then
    ok=1
  fi

  if (( USE_COLOR )); then
    printf '\r\033[2K'
  fi

  printf ' %s•%s %s\n' "$C_CYAN" "$C_OFF" "$label"
  if (( ok )); then
    local detail
    for detail in "$@"; do
      printf '   %s✔%s %s\n' "$C_GREEN" "$C_OFF" "$detail"
    done
  else
    printf '   %s✘%s %s\n' "$C_RED" "$C_OFF" "failed"
  fi
  printf '\n'
}

visible_len() {
  local stripped
  stripped=$(printf '%s' "$1" | sed 's/\x1b\[[0-9;]*m//g')
  printf '%s' "${#stripped}"
}

callout() {
  local title="$1"
  shift
  local -a lines=("$@")
  local width=62
  local inner=$((width - 2))
  local dash dashlen line pad vis

  dashlen=$((width - 4 - ${#title}))
  (( dashlen < 1 )) && dashlen=1
  printf -v dash '%*s' "$dashlen" ''
  dash="${dash// /─}"

  printf ' %s┌ %s%s%s %s┐%s\n' "$C_CYAN" "$C_BOLD" "$title" "$C_OFF$C_CYAN" "$dash" "$C_OFF"
  printf ' %s│%s %*s%s│%s\n' "$C_CYAN" "$C_OFF" "$((inner - 1))" '' "$C_CYAN" "$C_OFF"
  for line in "${lines[@]}"; do
    vis=$(visible_len "$line")
    pad=$((inner - 2 - vis))
    (( pad < 0 )) && pad=0
    printf ' %s│%s  %s%*s%s│%s\n' "$C_CYAN" "$C_OFF" "$line" "$pad" '' "$C_CYAN" "$C_OFF"
  done
  printf ' %s│%s %*s%s│%s\n' "$C_CYAN" "$C_OFF" "$((inner - 1))" '' "$C_CYAN" "$C_OFF"
  printf -v dash '%*s' "$((width - 2))" ''
  dash="${dash// /─}"
  printf ' %s└%s┘%s\n\n' "$C_CYAN" "$dash" "$C_OFF"
}

# Future work lives in these functions. They are empty on purpose.
link_configs() { :; }
install_packages() { :; }
apply_theme() { :; }

header
task "Linking configs" link_configs "hypr" "waybar" "polaroid"
task "Installing packages" install_packages "pacman"
task "Applying theme" apply_theme "polaroid"

callout "Machine ready" \
  "Nothing was installed, linked, or themed." \
  "" \
  "A new Omarchy machine starts from this script." \
  "" \
  "${C_BOLD}Same desk. New machine.${C_OFF}"
