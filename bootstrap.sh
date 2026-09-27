#!/usr/bin/env bash
# Omarchy checklist. Safe to re-run.
# Checks first. Offers checkboxes only for what is missing:
# Dropbox and Vault, Chromium, Bitwarden, then the rest of Dropbox.
# Writes the Chromium Bookmarks file to or from Vault, and a Chromium
# policy that force-installs uBlock Origin Lite.
# curl -fsSL https://raw.githubusercontent.com/LukasCaha/omarchy/main/bootstrap.sh | sh
#
# Public repo may later track only reviewed overlays:
#   config/hypr/bindings.conf
#   config/waybar/scripts/let-num*
#   config/omarchy/themes/polaroid
# Never commit: .env, KeePass, SSH keys, Chromium profile, bookmarks,
# cursor auth, gcloud/origin credentials, Wi-Fi, /etc/hosts, herdr config.toml
# (it can hold SSH targets). Those stay in Dropbox/Vault or the keyring.
# Bookmarks are copied as a file to ~/Dropbox/Vault/browser/chromium/Bookmarks.
# This script never prints their URLs.
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

STTY_SAVED=""
restore_tty() {
  if [[ -n "$STTY_SAVED" ]]; then
    stty "$STTY_SAVED" </dev/tty 2>/dev/null || stty sane </dev/tty 2>/dev/null || true
    STTY_SAVED=""
  fi
  printf '\033[?25h' >/dev/tty 2>/dev/null || true
}
cleanup() { restore_tty; printf '%s' "$C_OFF"; }
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
  printf ' %s INFO %s Checks first. Checkboxes appear only for what is missing.\n\n' "${C_INFO}${C_BOLD}" "$C_OFF"
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

tty_ok() { [[ -r /dev/tty && -w /dev/tty ]]; }

pause_tty() {
  tty_ok || return 1
  printf '   %s%s%s' "$C_DIM" "$1" "$C_OFF" >/dev/tty
  read -r _ </dev/tty || return 1
}

bitwarden_ready() {
  local f="$HOME/.config/Bitwarden/data.json"
  command -v bitwarden >/dev/null 2>&1 && [[ -f "$f" ]] && grep -q '"userId"' "$f" 2>/dev/null
}

dropbox_client_ready() {
  command -v dropbox >/dev/null 2>&1 || [[ -x "$HOME/.dropbox-dist/dropboxd" ]]
}

dropbox_running() {
  pgrep -f 'dropbox-lnx' >/dev/null 2>&1 || pgrep -x dropbox >/dev/null 2>&1
}

vault_ready() { [[ -d "$HOME/Dropbox/Vault" ]]; }

dropbox_rest_ready() {
  local d
  for d in Notes Resources Documents Images Personal; do
    [[ -d "$HOME/Dropbox/$d" ]] || return 1
  done
}

ublock_ready() {
  local id="ddkjiahejlhfcafbddmgiahcphecmpfh"
  local prefs="$HOME/.config/chromium/Default/Preferences"
  [[ -f "$prefs" ]] && grep -q "$id" "$prefs" 2>/dev/null
}

chromium_ready() {
  command -v chromium >/dev/null 2>&1 || return 1
  ublock_ready || return 1
  (( $(bookmark_urls "$HOME/.config/chromium/Default/Bookmarks") > 0 ))
}

start_dropbox() {
  dropbox_running && return 0
  if [[ -x "$HOME/.dropbox-dist/dropboxd" ]]; then
    setsid "$HOME/.dropbox-dist/dropboxd" >/dev/null 2>&1 &
  elif command -v dropbox >/dev/null 2>&1; then
    setsid dropbox start >/dev/null 2>&1 &
  fi
}

check_bitwarden() {
  section "Bitwarden"
  if ! command -v bitwarden >/dev/null 2>&1; then
    row fail "Bitwarden" "not installed"
  elif bitwarden_ready; then
    row pass "Bitwarden login" "account is on this machine"
  else
    row fail "Bitwarden login" "not logged in"
  fi
  printf '\n'
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
  if dropbox_client_ready && dropbox_running; then
    row pass "Dropbox client" "running"
  elif dropbox_client_ready; then
    row warn "Dropbox client" "installed, not running"
  else
    row fail "Dropbox client" "not installed"
  fi

  if vault_ready; then
    row pass "Vault" "synced locally"
  else
    row fail "Vault" "not on this machine"
  fi

  if dropbox_rest_ready; then
    row pass "Rest of Dropbox" "Notes, Resources, Documents, Images, Personal"
  else
    row fail "Rest of Dropbox" "working folders are not all here"
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
  section "Passwords"
  local vault="$HOME/Dropbox/Vault/main.kdbx"

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
  printf '\n'
}

bookmark_urls() {
  local f="$1"
  [[ -f "$f" ]] || { echo 0; return; }
  python3 - "$f" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(0)
    raise SystemExit
def count(node):
    if not isinstance(node, dict):
        return 0
    if node.get("type") == "url":
        return 1
    return sum(count(child) for child in node.get("children") or [])
roots = d.get("roots") or {}
print(sum(count(node) for node in roots.values()))
PY
}

check_browser() {
  section "Browser"
  local local_file="$HOME/.config/chromium/Default/Bookmarks"
  local vault_file="$HOME/Dropbox/Vault/browser/chromium/Bookmarks"
  local local_n=0 vault_n=0

  if command -v chromium >/dev/null 2>&1; then
    row pass "Chromium" "installed"
  else
    row fail "Chromium" "not installed"
    printf '\n'
    return
  fi

  local_n=$(bookmark_urls "$local_file")
  vault_n=$(bookmark_urls "$vault_file")

  if (( local_n > 0 )); then
    row pass "Bookmarks" "$local_n urls in the profile"
  elif (( vault_n > 0 )); then
    row fail "Bookmarks" "$vault_n urls in Vault, profile is empty"
  else
    row fail "Bookmarks" "none in the profile or in Vault"
  fi

  if ublock_ready; then
    row pass "uBlock Origin Lite" "installed"
  else
    row fail "uBlock Origin Lite" "not installed"
  fi
  printf '\n'
}

# Chromium 151 cannot run classic uBlock Origin. Lite is the current
# extension from the same author. The id is public; the extension itself
# is fetched from the Chrome Web Store when Chromium starts.
ensure_ublock() {
  local id="ddkjiahejlhfcafbddmgiahcphecmpfh"
  local policy_dir="/etc/chromium/policies/managed"
  local policy_file="$policy_dir/ublock.json"
  local update_url="https://clients2.google.com/service/update2/crx"
  local wanted="${id};${update_url}"
  local prefs="$HOME/.config/chromium/Default/Preferences"
  local installed=0

  if [[ -f "$prefs" ]] && grep -q "$id" "$prefs" 2>/dev/null; then
    installed=1
  fi

  if [[ ! -d "$policy_dir" || ! -w "$policy_dir" ]]; then
    row warn "uBlock Origin Lite" "Chromium policy directory is not writable"
    return
  fi

  if [[ ! -f "$policy_file" ]] || ! grep -q "$id" "$policy_file" 2>/dev/null; then
    cat >"$policy_file" <<EOF
{
  "ExtensionInstallForcelist": [
    "${wanted}"
  ]
}
EOF
  fi

  if (( installed )); then
    row pass "uBlock Origin Lite" "installed"
  else
    row warn "uBlock Origin Lite" "policy is set; restart Chromium to install it"
  fi
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

do_vault() {
  section "Dropbox and Vault"
  if ! dropbox_client_ready; then
    sudo pacman -S --needed --noconfirm dropbox </dev/tty
  fi
  start_dropbox
  if vault_ready; then
    row pass "Vault" "synced locally"
    printf '\n'
    return
  fi
  if pause_tty "Sign in to Dropbox and sync only Vault. Press Enter when ~/Dropbox/Vault is here. "; then
    if vault_ready; then
      row pass "Vault" "synced locally"
    else
      row warn "Vault" "still missing"
    fi
  else
    row warn "Vault" "sign in, then re-run"
  fi
  printf '\n'
}

do_dropbox_rest() {
  section "Rest of Dropbox"
  start_dropbox
  if dropbox_rest_ready; then
    row pass "Rest of Dropbox" "working folders are here"
    printf '\n'
    return
  fi
  if pause_tty "Turn on Notes, Resources, Documents, Images, and Personal. Leave Archive in the cloud. Press Enter when they are here. "; then
    if dropbox_rest_ready; then
      row pass "Rest of Dropbox" "working folders are here"
    else
      row warn "Rest of Dropbox" "some working folders are still missing"
    fi
  else
    row warn "Rest of Dropbox" "turn the folders on, then re-run"
  fi
  printf '\n'
}

sync_bookmarks() {
  local local_file="$HOME/.config/chromium/Default/Bookmarks"
  local vault_file="$HOME/Dropbox/Vault/browser/chromium/Bookmarks"
  local local_n vault_n
  local_n=$(bookmark_urls "$local_file")
  vault_n=$(bookmark_urls "$vault_file")

  if (( local_n > 0 )); then
    if [[ ! -d "$HOME/Dropbox/Vault" ]]; then
      row warn "Bookmarks" "$local_n urls in the profile, Vault is not here"
    elif [[ ! -f "$vault_file" ]] || [[ "$local_file" -nt "$vault_file" ]]; then
      mkdir -p "$(dirname "$vault_file")"
      cp -a "$local_file" "$vault_file"
      row pass "Bookmarks" "$local_n urls saved in Vault"
    else
      row pass "Bookmarks" "$local_n urls in the profile"
    fi
    return
  fi

  if (( vault_n > 0 )); then
    if pgrep -x chromium >/dev/null 2>&1; then
      row warn "Bookmarks" "quit Chromium, then re-run to restore $vault_n urls"
    else
      mkdir -p "$(dirname "$local_file")"
      cp -a "$vault_file" "$local_file"
      row pass "Bookmarks" "$vault_n urls restored from Vault"
    fi
  else
    row fail "Bookmarks" "none in the profile or in Vault"
  fi
}

do_chromium() {
  section "Chromium"
  if ! command -v chromium >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm chromium </dev/tty
  fi
  sync_bookmarks
  ensure_ublock
  printf '\n'
}

do_bitwarden() {
  section "Bitwarden"
  if ! command -v bitwarden >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm bitwarden </dev/tty
  fi
  if ! command -v bitwarden >/dev/null 2>&1; then
    row fail "Bitwarden" "not installed"
    printf '\n'
    return
  fi
  if ! pgrep -x bitwarden >/dev/null 2>&1; then
    setsid bitwarden >/dev/null 2>&1 &
  fi
  if bitwarden_ready; then
    row pass "Bitwarden login" "account is on this machine"
    printf '\n'
    return
  fi
  if pause_tty "Log in to Bitwarden and unlock the vault. Press Enter when that is done. "; then
    if bitwarden_ready; then
      row pass "Bitwarden login" "account is on this machine"
    else
      row warn "Bitwarden login" "Bitwarden is open; the account is not saved yet"
    fi
  else
    row warn "Bitwarden login" "log in, then re-run"
  fi
  printf '\n'
}

checkbox_menu() {
  local -a ids=("$@")
  local -a labels=()
  local -a on=()
  local id label i cur=0 n key
  CHOSEN=()
  for id in "${ids[@]}"; do
    case "$id" in
      vault) label="Dropbox and Vault" ;;
      chromium) label="Chromium bookmarks and uBlock" ;;
      bitwarden) label="Bitwarden" ;;
      dropbox_rest) label="Rest of Dropbox" ;;
      *) label="$id" ;;
    esac
    labels+=("$label")
    on+=(1)
  done
  n=${#ids[@]}
  tty_ok || return 1

  STTY_SAVED=$(stty -g </dev/tty)
  stty -echo -icanon min 0 time 1 </dev/tty
  printf '\033[?25l' >/dev/tty

  while true; do
    printf '\033[2K %sChoose what to set up%s  %sspace toggles, enter runs, q skips%s\n' \
      "$C_BOLD" "$C_OFF" "$C_DIM" "$C_OFF" >/dev/tty
    for i in "${!ids[@]}"; do
      local mark=" " box=" "
      (( on[i] )) && box="x"
      (( i == cur )) && mark=">"
      printf '\033[2K %s%s%s [%s] %s\n' "$C_CYAN" "$mark" "$C_OFF" "$box" "${labels[$i]}" >/dev/tty
    done

    key=""
    while [[ -z "$key" ]]; do
      IFS= read -rsn1 key </dev/tty || true
    done
    if [[ "$key" == $'\e' ]]; then
      local rest a b
      IFS= read -rsn1 -t 0.05 a </dev/tty || a=""
      IFS= read -rsn1 -t 0.05 b </dev/tty || b=""
      rest="${a}${b}"
      key+="$rest"
    fi

    case "$key" in
      j|$'\e[B') cur=$(( (cur + 1) % n )) ;;
      k|$'\e[A') cur=$(( (cur + n - 1) % n )) ;;
      ' ') on[cur]=$(( 1 - on[cur] )) ;;
      ''|$'\n'|$'\r')
        restore_tty
        for i in "${!ids[@]}"; do
          (( on[i] )) && CHOSEN+=("${ids[$i]}")
        done
        printf '\n' >/dev/tty
        return 0
        ;;
      q|$'\e')
        restore_tty
        CHOSEN=()
        printf '\n' >/dev/tty
        return 0
        ;;
    esac
    printf '\033[%dA' $((n + 1)) >/dev/tty
  done
}

offer_setup() {
  local -a missing=()
  local id
  vault_ready && dropbox_client_ready && dropbox_running || missing+=(vault)
  chromium_ready || missing+=(chromium)
  bitwarden_ready || missing+=(bitwarden)
  dropbox_rest_ready || missing+=(dropbox_rest)
  (( ${#missing[@]} )) || return 0

  if ! tty_ok; then
    printf ' %sStill open%s  %s\n\n' "$C_YEL" "$C_OFF" "${missing[*]}"
    return 0
  fi

  checkbox_menu "${missing[@]}"
  (( ${#CHOSEN[@]} )) || return 0

  for id in vault chromium bitwarden dropbox_rest; do
    local chosen
    for chosen in "${CHOSEN[@]}"; do
      if [[ "$chosen" == "$id" ]]; then
        "do_${id}"
      fi
    done
  done
}

header
check_dropbox
check_browser
check_bitwarden
check_projects
check_secrets
check_passwords
check_keybinds
check_herdr
check_configs
offer_setup

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
