#!/usr/bin/env bash
# Barebones Omarchy setup. Safe to re-run.
# 1. Dropbox service
# 2. Bitwarden desktop + CLI
# 3. Chromium: uBlock Origin Lite, Bitwarden extension, bookmarks, vertical tabs
# 4. Open Bitwarden sign-in (app and extension)
# 5. Open Dropbox sign-in
#
# Chromium cannot install classic uBlock Origin. The policy installs
# uBlock Origin Lite, which is what this machine already runs.
set -euo pipefail

UBLOCK_ID="ddkjiahejlhfcafbddmgiahcphecmpfh"
BITWARDEN_EXT_ID="nngceckbapebfimnlniiiahkandclblb"
UPDATE_URL="https://clients2.google.com/service/update2/crx"
POLICY_FILE="/etc/chromium/policies/managed/ublock.json"
PREFS="$HOME/.config/chromium/Default/Preferences"
BOOKMARKS="$HOME/.config/chromium/Default/Bookmarks"
VAULT_BOOKMARKS="$HOME/Dropbox/Vault/browser/chromium/Bookmarks"
BW_EXT_URL="chrome-extension://${BITWARDEN_EXT_ID}/popup/index.html"

say() { printf '%s\n' "$*"; }

pkg_installed() { pacman -Q "$1" &>/dev/null; }

chromium_running() { pgrep -x chromium >/dev/null 2>&1; }

dropbox_running() {
  pgrep -f 'dropbox-lnx' >/dev/null 2>&1 || pgrep -x dropbox >/dev/null 2>&1
}

dropbox_linked() { [[ -f "$HOME/.dropbox/info.json" ]]; }

bitwarden_app_logged_in() {
  local f="$HOME/.config/Bitwarden/data.json"
  [[ -f "$f" ]] && grep -q '"userId"' "$f"
}

bitwarden_ext_logged_in() {
  local dir="$HOME/.config/chromium/Default/Local Extension Settings/${BITWARDEN_EXT_ID}"
  [[ -d "$dir" ]] && grep -a -q 'emailVerified' "$dir"/* 2>/dev/null
}

extension_installed() {
  [[ -f "$PREFS" ]] && grep -q "$1" "$PREFS"
}

bookmark_count() {
  python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    print(0)
    raise SystemExit
def count(node):
    if not isinstance(node, dict):
        return 0
    if node.get("type") == "url":
        return 1
    return sum(count(child) for child in node.get("children") or [])
roots = data.get("roots") or {}
print(sum(count(node) for node in roots.values()))
PY
}

write_extension_policy() {
  local dir body
  dir=$(dirname "$POLICY_FILE")
  body=$(cat <<EOF
{
  "ExtensionInstallForcelist": [
    "${UBLOCK_ID};${UPDATE_URL}",
    "${BITWARDEN_EXT_ID};${UPDATE_URL}"
  ]
}
EOF
)
  if [[ -f "$POLICY_FILE" ]] && grep -q "$UBLOCK_ID" "$POLICY_FILE" && grep -q "$BITWARDEN_EXT_ID" "$POLICY_FILE"; then
    say "extension policy already set"
    return
  fi
  if [[ -w "$dir" ]]; then
    printf '%s\n' "$body" >"$POLICY_FILE"
  else
    printf '%s\n' "$body" | sudo tee "$POLICY_FILE" >/dev/null
  fi
  say "extension policy written"
}

enable_vertical_tabs() {
  if chromium_running; then
    say "Chromium is open. Quit it and re-run to turn on vertical tabs."
    return
  fi
  python3 - "$PREFS" <<'PY'
import json, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path):
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
tabs = data.get("vertical_tabs") if isinstance(data.get("vertical_tabs"), dict) else {}
tabs["enabled"] = True
data["vertical_tabs"] = tabs
with open(path, "w") as fh:
    json.dump(data, fh)
PY
  say "vertical tabs on"
}

restore_bookmarks() {
  if [[ ! -f "$VAULT_BOOKMARKS" ]]; then
    say "no bookmark file in Vault yet"
    return
  fi
  local have=0
  if [[ -f "$BOOKMARKS" ]]; then
    have=$(bookmark_count "$BOOKMARKS")
  fi
  if (( have > 0 )); then
    say "bookmarks already in the profile ($have)"
    return
  fi
  if chromium_running; then
    say "Chromium is open. Quit it and re-run to restore bookmarks."
    return
  fi
  mkdir -p "$(dirname "$BOOKMARKS")"
  cp -a "$VAULT_BOOKMARKS" "$BOOKMARKS"
  say "bookmarks restored from Vault"
}

open_url() {
  setsid xdg-open "$1" >/dev/null 2>&1 &
}

say "1. Dropbox"
if ! pkg_installed dropbox; then
  omarchy-install-dropbox
else
  say "Dropbox already installed"
  if ! dropbox_running && command -v dropbox-cli >/dev/null 2>&1; then
    uwsm-app -- dropbox-cli start &>/dev/null &
  fi
fi

say "2. Bitwarden"
if pkg_installed bitwarden && pkg_installed bitwarden-cli; then
  say "Bitwarden already installed"
else
  omarchy-pkg-add bitwarden bitwarden-cli
fi

say "3. Chromium"
if pkg_installed chromium; then
  say "Chromium already installed"
else
  omarchy-pkg-add chromium
fi
write_extension_policy
if extension_installed "$UBLOCK_ID"; then
  say "uBlock Origin Lite installed"
else
  say "uBlock Origin Lite installs the next time Chromium starts"
fi
if extension_installed "$BITWARDEN_EXT_ID"; then
  say "Bitwarden extension installed"
else
  say "Bitwarden extension installs the next time Chromium starts"
fi
restore_bookmarks
enable_vertical_tabs

say "4. Bitwarden sign-in"
if bitwarden_app_logged_in; then
  say "Bitwarden app already signed in"
else
  setsid gtk-launch bitwarden >/dev/null 2>&1 &
  say "opened the Bitwarden app"
fi
if bitwarden_ext_logged_in; then
  say "Bitwarden extension already signed in"
else
  setsid chromium "$BW_EXT_URL" >/dev/null 2>&1 &
  say "opened the Bitwarden extension. Sign in there too. The app login does not fill the extension."
fi

say "5. Dropbox sign-in"
if dropbox_linked; then
  say "Dropbox already signed in"
else
  open_url "https://www.dropbox.com/login"
  say "opened the Dropbox sign-in page"
fi
