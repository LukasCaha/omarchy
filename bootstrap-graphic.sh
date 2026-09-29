#!/usr/bin/env bash
# Omarchy checklist. Safe to re-run.
# Checks Dropbox, Bitwarden, and Chromium.
# Opens the sign-in for whichever is missing, then continues on its own.
# Writes the Chromium Bookmarks file to or from Vault, and a Chromium
# policy that force-installs uBlock Origin Lite and the Bitwarden extension.
# curl -fsSL https://raw.githubusercontent.com/LukasCaha/omarchy/main/bootstrap-graphic.sh | sh
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
  [[ -r /dev/tty && -w /dev/tty ]] || return 0
  if [[ -n "$STTY_SAVED" ]]; then
    stty "$STTY_SAVED" </dev/tty 2>/dev/null || stty sane </dev/tty 2>/dev/null || true
    STTY_SAVED=""
  fi
  printf '\033[?25h' >/dev/tty 2>/dev/null || true
}
cleanup() { restore_tty; printf '%s' "$C_OFF"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

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
  printf ' %s INFO %s Dropbox, Bitwarden, then Chromium. Sign-in opens only when it is missing.\n\n' "${C_INFO}${C_BOLD}" "$C_OFF"
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

bitwarden_ready() {
  local f="$HOME/.config/Bitwarden/data.json"
  command -v bitwarden >/dev/null 2>&1 && [[ -f "$f" ]] && grep -q '"userId"' "$f" 2>/dev/null
}

dropbox_linked() {
  [[ -f "$HOME/.dropbox/info.json" ]] || vault_ready
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

UBLOCK_ID="ddkjiahejlhfcafbddmgiahcphecmpfh"
BITWARDEN_EXT_ID="nngceckbapebfimnlniiiahkandclblb"

extension_installed() {
  local prefs="$HOME/.config/chromium/Default/Preferences"
  [[ -f "$prefs" ]] && grep -q "$1" "$prefs" 2>/dev/null
}

extensions_ready() {
  extension_installed "$UBLOCK_ID" && extension_installed "$BITWARDEN_EXT_ID"
}

chromium_ready() {
  command -v chromium >/dev/null 2>&1 || return 1
  extensions_ready || return 1
  (( $(bookmark_urls "$HOME/.config/chromium/Default/Bookmarks") > 0 ))
}

start_dropbox() {
  dropbox_running && return 0
  if command -v dropbox >/dev/null 2>&1; then
    setsid dropbox start -i >/dev/null 2>&1 &
  elif [[ -x "$HOME/.dropbox-dist/dropboxd" ]]; then
    setsid "$HOME/.dropbox-dist/dropboxd" >/dev/null 2>&1 &
  fi
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

# Chromium 151 cannot run classic uBlock Origin. Lite is the current
# extension from the same author. Both ids are public. Chromium downloads
# the extensions from the Chrome Web Store when it starts.
# One policy file holds the whole force-install list. A second file with
# the same key would replace the list instead of adding to it.
ensure_extensions() {
  local policy_dir="/etc/chromium/policies/managed"
  local policy_file="$policy_dir/extensions.json"
  local update_url="https://clients2.google.com/service/update2/crx"
  local id label

  if [[ ! -d "$policy_dir" || ! -w "$policy_dir" ]]; then
    row warn "Chromium extensions" "policy directory is not writable"
    return
  fi

  if [[ ! -f "$policy_file" ]] || ! grep -q "$UBLOCK_ID" "$policy_file" 2>/dev/null || ! grep -q "$BITWARDEN_EXT_ID" "$policy_file" 2>/dev/null; then
    cat >"$policy_file" <<EOF
{
  "ExtensionInstallForcelist": [
    "${UBLOCK_ID};${update_url}",
    "${BITWARDEN_EXT_ID};${update_url}"
  ]
}
EOF
  fi
  rm -f "$policy_dir/ublock.json"

  for id in "$UBLOCK_ID" "$BITWARDEN_EXT_ID"; do
    if [[ "$id" == "$UBLOCK_ID" ]]; then
      label="uBlock Origin Lite"
    else
      label="Bitwarden"
    fi
    if extension_installed "$id"; then
      row pass "$label" "installed"
    else
      row warn "$label" "policy is set; Chromium installs it on the next start"
    fi
  done
}

install_pkg() {
  local bin="$1" pkg="$2"
  command -v "$bin" >/dev/null 2>&1 && return 0
  sudo pacman -S --needed --noconfirm "$pkg" </dev/tty
}

open_page() {
  command -v xdg-open >/dev/null 2>&1 || return 0
  setsid xdg-open "$1" >/dev/null 2>&1 &
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

bootstrap_accounts() {
  local db=0 bw=0 cr=0 synced=0
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=0 msg

  section "Accounts"
  if dropbox_linked; then
    row pass "Dropbox" "signed in"
    db=1
  else
    row fail "Dropbox" "not signed in"
  fi
  if bitwarden_ready; then
    row pass "Bitwarden" "signed in"
    bw=1
  else
    row fail "Bitwarden" "not signed in"
  fi
  if chromium_ready; then
    row pass "Chromium" "bookmarks, uBlock, and Bitwarden are in place"
    cr=1
  else
    row fail "Chromium" "not synced yet"
  fi
  printf '\n'

  if ! command -v chromium >/dev/null 2>&1; then
    install_pkg chromium chromium
  fi
  if command -v chromium >/dev/null 2>&1; then
    ensure_extensions
    printf '\n'
    if extensions_ready && (( $(bookmark_urls "$HOME/.config/chromium/Default/Bookmarks") > 0 )); then
      cr=1
    fi
  fi

  if (( db && bw && cr )) && dropbox_rest_ready; then
    return 0
  fi

  if (( ! db )); then
    install_pkg dropbox dropbox
    start_dropbox
    open_page "https://www.dropbox.com/login"
    printf '   %sOpened the Dropbox sign-in page.%s\n' "$C_DIM" "$C_OFF"
    printf '   %sA 6-digit code is Dropbox'\''s own device check. On the computer already signed in, open dropbox.com, Settings, Security. If 2-factor is on, turn it off and link again. If it is off, the code is in email.%s\n' "$C_DIM" "$C_OFF"
  fi
  if (( ! bw )); then
    install_pkg bitwarden bitwarden
    if command -v bitwarden >/dev/null 2>&1 && ! pgrep -x bitwarden >/dev/null 2>&1; then
      setsid bitwarden >/dev/null 2>&1 &
    fi
    printf '   %sOpened Bitwarden. Sign in in that window so this machine keeps the account.%s\n' "$C_DIM" "$C_OFF"
  fi
  while (( ! db || ! bw || ! cr )) || ! dropbox_rest_ready; do
    if dropbox_linked; then db=1; fi
    if bitwarden_ready; then bw=1; fi
    if (( db && ! cr )) && vault_ready; then
      local local_n=0
      local_n=$(bookmark_urls "$HOME/.config/chromium/Default/Bookmarks")
      if (( local_n > 0 )) || ! pgrep -x chromium >/dev/null 2>&1; then
        if (( ! synced )); then
          printf '\n'
          sync_bookmarks
          ensure_extensions
          if extensions_ready; then cr=1; fi
          printf '\n'
          synced=1
        fi
      fi
      if (( synced )) && ! extensions_ready && ! pgrep -x chromium >/dev/null 2>&1; then
        setsid chromium >/dev/null 2>&1 &
      fi
    fi
    if chromium_ready; then cr=1; fi

    if (( db && bw && cr )) && dropbox_rest_ready; then
      break
    fi
    if (( ! db )); then msg="Sign in to Dropbox in the browser"
    elif (( ! bw )); then msg="Sign in to Bitwarden in the window that opened"
    elif ! vault_ready; then msg="Waiting for the Vault folder"
    elif (( $(bookmark_urls "$HOME/.config/chromium/Default/Bookmarks") == 0 )) && pgrep -x chromium >/dev/null 2>&1; then
      msg="Quit Chromium so bookmarks can be restored"
    elif ! extensions_ready; then msg="Chromium is installing uBlock Origin Lite and Bitwarden"
    else msg="In Dropbox, turn on Notes, Resources, Documents, Images, and Personal"
    fi
    if (( USE_COLOR )); then
      printf '\r\033[2K %s%s%s %s' "$C_CYAN" "${frames[$((i % 10))]}" "$C_OFF" "$msg"
    else
      printf '%s\n' "$msg"
    fi
    i=$((i + 1))
    sleep 2
  done
  printf '\r\033[2K\n'
}

header
bootstrap_accounts

callout "Machine ready" \
  "Dropbox, Bitwarden, and Chromium are in place." \
  "" \
  "${C_BOLD}Same desk. New machine.${C_OFF}"
