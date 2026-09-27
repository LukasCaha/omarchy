#!/usr/bin/env bash
# Omarchy checklist. Safe to re-run. Changes nothing.
# curl -fsSL https://raw.githubusercontent.com/LukasCaha/omarchy/main/bootstrap.sh | sh
#
# Public repo may later track only reviewed overlays:
#   config/hypr/bindings.conf
#   config/waybar/scripts/let-num*
#   config/omarchy/themes/polaroid
# Never commit: .env, KeePass, SSH keys, Chromium profile, cursor auth,
# gcloud/origin credentials, Wi-Fi, /etc/hosts, herdr config.toml
# (it can hold SSH targets). Those stay in Dropbox/Vault or the keyring.
set -uo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YEL=$'\033[33m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_OFF=$'\033[0m'
  C_INFO=$'\033[44;30m'
  USE_COLOR=1
else
  C_CYAN= C_GREEN= C_YEL= C_RED= C_DIM= C_BOLD= C_OFF= C_INFO=
  USE_COLOR=0
fi

PASS_N=0
WARN_N=0
FAIL_N=0

cleanup() { printf '%s\033[?25h' "$C_OFF"; }
trap cleanup EXIT INT TERM

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

ROOT=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

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
  printf ' %s INFO %s Checklist only. Re-run it as often as you want. Nothing is changed.\n\n' "${C_INFO}${C_BOLD}" "$C_OFF"
}

section() {
  local label="$1"
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i
  if (( USE_COLOR )); then
    printf '\033[?25l'
    for i in 0 1 2 3 4 5; do
      printf '\r\033[2K %s%s%s %s' "$C_CYAN" "${frames[$i]}" "$C_OFF" "$label"
      sleep 0.04
    done
    printf '\033[?25h\r\033[2K'
  fi
  printf ' %s•%s %s\n' "$C_CYAN" "$C_OFF" "$label"
}

row() {
  local status="$1" label="$2" detail="${3:-}"
  local icon color
  case "$status" in
    pass) icon='✔'; color="$C_GREEN"; PASS_N=$((PASS_N + 1)) ;;
    warn) icon='▲'; color="$C_YEL"; WARN_N=$((WARN_N + 1)) ;;
    fail) icon='✘'; color="$C_RED"; FAIL_N=$((FAIL_N + 1)) ;;
    *)    icon='·'; color="$C_DIM" ;;
  esac
  printf '   %s%s%s %s' "$color" "$icon" "$C_OFF" "$label"
  if [[ -n "$detail" ]]; then
    printf '  %s%s%s' "$C_DIM" "$detail" "$C_OFF"
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

age_days() {
  local f="$1" now mtime
  [[ -e "$f" ]] || { echo 9999; return; }
  now=$(date +%s)
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  echo $(( (now - mtime) / 86400 ))
}

check_dropbox() {
  section "Dropbox"
  local client=0 running=0
  if command -v dropbox >/dev/null 2>&1 || [[ -x "$HOME/.dropbox-dist/dropboxd" ]]; then
    client=1
  fi
  if pgrep -f 'dropbox-lnx' >/dev/null 2>&1 || pgrep -x dropbox >/dev/null 2>&1; then
    running=1
  fi

  if (( client && running )); then
    row pass "Dropbox client" "running"
  elif (( client )); then
    row warn "Dropbox client" "installed, not running"
  else
    row fail "Dropbox client" "not installed"
  fi

  if [[ -d "$HOME/Dropbox/Vault" && -d "$HOME/Dropbox/Notes" ]]; then
    row pass "Vault and Notes" "synced locally"
  elif [[ -d "$HOME/Dropbox" ]]; then
    row warn "Vault and Notes" "Dropbox is here, those folders are not"
  else
    row fail "Vault and Notes" "sign in to Dropbox first"
  fi
  printf '\n'
}

check_projects() {
  section "Projects"
  local dir name git_n=0 other_n=0
  if [[ ! -d "$HOME/Projects" ]]; then
    row fail "Projects directory" "missing ~/Projects"
    row warn "GitHub login" "waiting on Projects"
    printf '\n'
    return
  fi

  shopt -s nullglob
  for dir in "$HOME/Projects"/*/; do
    name=$(basename "$dir")
    [[ "$name" == .* ]] && continue
    if [[ -d "$dir/.git" ]]; then
      git_n=$((git_n + 1))
    else
      other_n=$((other_n + 1))
    fi
  done
  shopt -u nullglob

  if (( git_n > 0 && other_n == 0 )); then
    row pass "Repositories" "$git_n git repos"
  elif (( git_n > 0 )); then
    row warn "Repositories" "$git_n git, $other_n not git"
  else
    row fail "Repositories" "none cloned yet"
  fi

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    row pass "GitHub login" "gh can clone private repos"
  else
    row fail "GitHub login" "run gh auth login on this machine"
  fi
  printf '\n'
}

check_secrets() {
  section "Secrets"
  local env_root="$HOME/Dropbox/Vault/LaravelEnvs"
  local newest="" edays=9999
  local dir name need=0 have=0
  local -a missing=()

  if [[ -d "$env_root" ]]; then
    newest=$(find "$env_root" -mindepth 1 -maxdepth 1 -type d -name 'envs_*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)
  fi
  if [[ -n "$newest" ]]; then
    edays=$(age_days "$newest")
    if (( edays <= 30 )); then
      row pass "Env backup in Vault" "$(basename "$newest") · ${edays}d ago"
    else
      row warn "Env backup in Vault" "$(basename "$newest") · ${edays}d ago"
    fi
  elif [[ -d "$HOME/Dropbox/Vault" ]]; then
    row fail "Env backup in Vault" "no envs_* snapshot"
  else
    row fail "Env backup in Vault" "Vault is not on this machine"
  fi

  if [[ -d "$HOME/Projects" ]]; then
    shopt -s nullglob
    for dir in "$HOME/Projects"/*/; do
      [[ -f "$dir/.env.example" || -f "$dir/artisan" ]] || continue
      name=$(basename "$dir")
      if [[ -f "$dir/.env" ]]; then
        have=$((have + 1))
      else
        need=$((need + 1))
        if (( ${#missing[@]} < 4 )); then
          missing+=("$name")
        fi
      fi
    done
    shopt -u nullglob
  fi

  if (( need == 0 && have > 0 )); then
    row pass "Repo .env files" "$have present, none missing"
  elif (( need > 0 && have > 0 )); then
    row warn "Repo .env files" "$have present, $need missing (${missing[*]})"
  elif (( need > 0 )); then
    row fail "Repo .env files" "$need missing (${missing[*]})"
  else
    row warn "Repo .env files" "no Laravel apps cloned yet"
  fi
  printf '\n'
}

check_passwords() {
  section "Passwords and browser"
  local vault="$HOME/Dropbox/Vault/main.kdbx"
  local bookmarks="$HOME/.config/chromium/Default/Bookmarks"

  if [[ -f "$vault" ]]; then
    row pass "KeePass vault" "in Dropbox"
  else
    row fail "KeePass vault" "not in ~/Dropbox/Vault"
  fi

  if timeout 2 secret-tool lookup keepass keepassxc >/dev/null 2>&1; then
    row pass "KeePass auto-unlock" "keyring has the password"
  else
    row warn "KeePass auto-unlock" "keyring entry missing on this login"
  fi

  if [[ -f "$bookmarks" ]]; then
    row pass "Chromium bookmarks" "profile is on this machine"
  else
    row fail "Chromium bookmarks" "sign in or copy the profile"
  fi
  printf '\n'
}

check_keybinds() {
  section "Keybinds"
  local bindings="$HOME/.config/hypr/bindings.conf"
  local hypr="$HOME/.config/hypr/hyprland.conf"
  local custom=0

  if [[ -f "$bindings" ]]; then
    row pass "Omarchy bindings" "defaults are on disk"
  else
    row fail "Omarchy bindings" "bindings.conf missing"
  fi

  if [[ -f "$bindings" ]] && grep -q '1password' "$bindings" 2>/dev/null; then
    custom=1
  fi
  if [[ -f "$hypr" ]] && grep -q 'special:scratchpad' "$hypr" 2>/dev/null; then
    custom=1
  fi
  if (( custom )); then
    row pass "Custom keybinds" "scratchpad or 1Password is bound"
  else
    row warn "Custom keybinds" "still Omarchy defaults"
  fi
  printf '\n'
}

check_herdr() {
  section "herdr"
  if command -v herdr >/dev/null 2>&1; then
    row pass "herdr binary" "on PATH"
  else
    row fail "herdr binary" "not installed"
  fi
  if [[ -f "$HOME/.config/herdr/config.toml" ]]; then
    row pass "herdr config" "local config.toml present"
  else
    row warn "herdr config" "no local config yet"
  fi
  printf '\n'
}

check_configs() {
  section "Configs"
  if [[ -f "$HOME/.config/hypr/hyprland.conf" && -f "$HOME/.config/waybar/config.jsonc" ]]; then
    row pass "Omarchy defaults" "hypr and waybar are on disk"
  else
    row fail "Omarchy defaults" "hypr or waybar config missing"
  fi

  if [[ -d "$HOME/.config/omarchy/themes/polaroid" && ! -L "$HOME/.config/omarchy/themes/polaroid" ]]; then
    row pass "Polaroid theme" "custom theme is on this machine"
  else
    row warn "Polaroid theme" "not brought over; stock theme stays"
  fi

  if compgen -G "$HOME/.config/waybar/scripts/let-num*" >/dev/null; then
    row pass "Waybar scripts" "let-num scripts present"
  else
    row warn "Waybar scripts" "stock waybar, scripts not copied"
  fi

  if [[ -n "$ROOT" && -d "$ROOT/config" ]]; then
    row pass "Repo overlay" "config/ is in the checkout"
  else
    row warn "Repo overlay" "public repo tracks no configs yet"
  fi
  printf '\n'
}

header
check_dropbox
check_projects
check_secrets
check_passwords
check_keybinds
check_herdr
check_configs

printf ' %s%d done%s  %s%d waiting%s  %s%d missing%s\n\n' \
  "$C_GREEN" "$PASS_N" "$C_OFF" \
  "$C_YEL" "$WARN_N" "$C_OFF" \
  "$C_RED" "$FAIL_N" "$C_OFF"

if (( FAIL_N == 0 && WARN_N == 0 )); then
  callout "Machine ready" \
    "Every check passed." \
    "" \
    "${C_BOLD}Same desk. New machine.${C_OFF}"
else
  callout "Still setting up" \
    "Re-run after each thing you finish." \
    "Waiting items are defaults we have not copied." \
    "" \
    "Secrets stay in Vault. This repo stays public." \
    "" \
    "${C_BOLD}Same desk. New machine.${C_OFF}"
fi
