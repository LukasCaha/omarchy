#!/usr/bin/env bash
# Barebones setup for Omarchy 4.0.4. Safe to re-run.
# 1. Dropbox service          omarchy-install-service-dropbox
# 2. Bitwarden service        omarchy-pkg-add bitwarden bitwarden-cli
# 3. Chromium: uBlock Origin Lite, Bitwarden extension, bookmarks, vertical tabs
# 4. Open Bitwarden sign-in (app and extension)
# 5. Open Dropbox sign-in
#
# Chromium cannot install classic uBlock Origin. The policy installs
# uBlock Origin Lite. On 4.0.4 the policy file has to be root-owned or
# the next theme refresh deletes it.
set -euo pipefail

UBLOCK_ID="ddkjiahejlhfcafbddmgiahcphecmpfh"
BITWARDEN_EXT_ID="nngceckbapebfimnlniiiahkandclblb"
UPDATE_URL="https://clients2.google.com/service/update2/crx"
POLICY_DIR="/etc/chromium/policies/managed"
POLICY_FILE="$POLICY_DIR/extensions.json"
PREFS="$HOME/.config/chromium/Default/Preferences"
BOOKMARKS="$HOME/.config/chromium/Default/Bookmarks"
VAULT_BOOKMARKS="$HOME/Dropbox/Vault/browser/chromium/Bookmarks"
BW_EXT_URL="chrome-extension://${BITWARDEN_EXT_ID}/popup/index.html"

say() { printf '%s\n' "$*"; }

pkg_present() {
  if command -v omarchy-pkg-present >/dev/null 2>&1; then
    omarchy-pkg-present "$@"
  else
    pacman -Q "$@" &>/dev/null
  fi
}

launch() {
  setsid uwsm-app -- "$@" >/dev/null 2>&1 &
}

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
  local tmp
  if [[ -f "$POLICY_FILE" ]] && grep -q "$UBLOCK_ID" "$POLICY_FILE" && grep -q "$BITWARDEN_EXT_ID" "$POLICY_FILE"; then
    say "extension policy already set"
    return
  fi
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
{
  "ExtensionInstallForcelist": [
    "${UBLOCK_ID};${UPDATE_URL}",
    "${BITWARDEN_EXT_ID};${UPDATE_URL}"
  ]
}
EOF
  sudo install -d -m 0755 -o root -g root "$POLICY_DIR"
  sudo install -m 0644 -o root -g root -T "$tmp" "$POLICY_FILE"
  rm -f "$tmp"
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

say "1. Dropbox"
if pkg_present dropbox; then
  say "Dropbox already installed"
  if ! dropbox_running; then
    launch dropbox-cli start
  fi
else
  if ! command -v omarchy-install-service-dropbox >/dev/null 2>&1; then
    say "omarchy-install-service-dropbox is not on PATH. This script targets Omarchy 4.0.4."
    exit 1
  fi
  omarchy-install-service-dropbox
fi

say "2. Bitwarden"
if pkg_present bitwarden bitwarden-cli; then
  say "Bitwarden already installed"
else
  omarchy-pkg-add bitwarden bitwarden-cli
fi

say "3. Chromium"
if pkg_present chromium; then
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
  launch gtk-launch bitwarden
  say "opened the Bitwarden app"
fi
if bitwarden_ext_logged_in; then
  say "Bitwarden extension already signed in"
else
  launch chromium "$BW_EXT_URL"
  say "opened the Bitwarden extension. Sign in there too. The app login does not fill the extension."
fi

say "5. Dropbox sign-in"
if dropbox_linked; then
  say "Dropbox already signed in"
else
  launch xdg-open "https://www.dropbox.com/login"
  say "opened the Dropbox sign-in page"
fi
