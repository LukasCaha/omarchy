#!/usr/bin/env bash
# Barebones setup for Omarchy 4.0.4. Safe to re-run.
# 0. Czech QWERTZ, before any password
# 1. Dropbox service, then its own sign-in (the tray, not dropbox.com)
# 2. Bitwarden desktop, one sign-in, then the PC login unlocks it
# 3. Chromium bookmarks, vertical tabs, uBlock Origin Lite, Bitwarden extension
set -euo pipefail

UBLOCK_ID="ddkjiahejlhfcafbddmgiahcphecmpfh"
BITWARDEN_EXT_ID="nngceckbapebfimnlniiiahkandclblb"
UPDATE_URL="https://clients2.google.com/service/update2/crx"
POLICY_DIR="/etc/chromium/policies/managed"
POLICY_FILE="$POLICY_DIR/extensions.json"
PREFS="$HOME/.config/chromium/Default/Preferences"
BOOKMARKS="$HOME/.config/chromium/Default/Bookmarks"
VAULT_BOOKMARKS="$HOME/Dropbox/Vault/browser/chromium/Bookmarks"
INPUT_LUA="$HOME/.config/hypr/input.lua"
POLKIT_RULE="/etc/polkit-1/rules.d/49-bitwarden-session.rules"
POLKIT_POLICY="/usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy"

say() { printf '%s\n' "$*"; }

pkg_present() {
  if command -v omarchy-pkg-present >/dev/null 2>&1; then
    omarchy-pkg-present "$@"
  else
    pacman -Q "$@" &>/dev/null
  fi
}

chromium_running() { pgrep -x chromium >/dev/null 2>&1; }

dropbox_running() {
  pgrep -f 'dropbox-lnx' >/dev/null 2>&1 || pgrep -x dropbox >/dev/null 2>&1
}

dropbox_linked() { [[ -f "$HOME/.dropbox/info.json" ]]; }

bitwarden_app_logged_in() {
  local f="$HOME/.config/Bitwarden/data.json"
  [[ -f "$f" ]] || return 1
  python3 - "$f" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
active = data.get("global_account_activeAccountId")
if isinstance(active, str) and len(active) > 8:
    raise SystemExit(0)
accounts = data.get("global_account_accounts")
if isinstance(accounts, dict) and accounts:
    raise SystemExit(0)
raise SystemExit(1)
PY
}

set_bitwarden_eu() {
  python3 - "$HOME/.config/Bitwarden/data.json" <<'PY'
import json, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        data = json.load(open(path))
    except Exception:
        data = {}
active = data.get("global_account_activeAccountId")
accounts = data.get("global_account_accounts")
if (isinstance(active, str) and len(active) > 8) or (isinstance(accounts, dict) and accounts):
    raise SystemExit(0)
data["global_environment_environment"] = {
    "region": "EU",
    "urls": {
        "base": None,
        "api": "https://api.bitwarden.eu",
        "identity": "https://identity.bitwarden.eu",
        "icons": "https://icons.bitwarden.eu",
        "notifications": "https://notifications.bitwarden.eu",
        "events": "https://events.bitwarden.eu",
        "webVault": "https://vault.bitwarden.eu",
        "keyConnector": None,
        "send": "https://vault.bitwarden.eu",
    },
}
tmp = path + ".bootstrap"
with open(tmp, "w") as fh:
    json.dump(data, fh)
os.replace(tmp, path)
PY
  if command -v bw >/dev/null 2>&1; then
    bw config server https://vault.bitwarden.eu >/dev/null 2>&1 || true
  fi
}

close_chromium() {
  chromium_running || return 0
  say "Closing Chromium so the profile can be written."
  killall chromium 2>/dev/null || true
  local _
  for _ in $(seq 1 30); do
    chromium_running || return 0
    sleep 0.5
  done
  say "Chromium is still running. Quit it, then re-run."
  exit 1
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

# Czech QWERTZ. Applied now, and saved for the next login.
# Omarchy 4 reads ~/.config/hypr/input.lua after its defaults.
set_keyboard() {
  say "0. Keyboard"
  hyprctl keyword input:kb_layout cz >/dev/null
  hyprctl keyword input:kb_variant '' >/dev/null
  hyprctl keyword input:kb_options 'compose:caps,shift:both_capslock_cancel' >/dev/null
  mkdir -p "$(dirname "$INPUT_LUA")"
  if [[ ! -f "$INPUT_LUA" ]] || ! grep -q 'kb_layout = "cz"' "$INPUT_LUA"; then
    cat >>"$INPUT_LUA" <<'EOF'

-- Czech QWERTZ. Written by bootstrap-2.sh.
hl.config({
  input = {
    kb_layout = "cz",
    kb_variant = "",
    kb_options = "compose:caps,shift:both_capslock_cancel",
  },
})
EOF
  fi
  if [[ -f /etc/vconsole.conf ]] && grep -q '^KEYMAP=cz$' /etc/vconsole.conf && grep -q '^XKBLAYOUT=cz$' /etc/vconsole.conf; then
    :
  else
    local tmp rest
    tmp=$(mktemp)
    rest=$(grep -v -E '^(KEYMAP|XKBLAYOUT)=' /etc/vconsole.conf 2>/dev/null || true)
    printf '%s\nKEYMAP=cz\nXKBLAYOUT=cz\n' "$rest" >"$tmp"
    sudo install -m 0644 -o root -g root -T "$tmp" /etc/vconsole.conf
    rm -f "$tmp"
  fi
  if [[ -f "$HOME/.config/fcitx5/profile" ]]; then
    sed -i \
      -e 's/^Default Layout=.*/Default Layout=cz/' \
      -e 's/^DefaultIM=.*/DefaultIM=keyboard-cz/' \
      -e 's/^Name=keyboard-us$/Name=keyboard-cz/' \
      "$HOME/.config/fcitx5/profile"
    fcitx5-remote -r >/dev/null 2>&1 || true
  fi
  say "Czech QWERTZ is on. Type passwords with that layout."
}

start_dropbox() {
  if dropbox_running; then
    return 0
  fi
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- dropbox-cli start
  else
    dropbox-cli start
  fi
  local _
  for _ in $(seq 1 20); do
    dropbox_running && return 0
    sleep 0.5
  done
  say "Dropbox did not stay running."
  return 1
}

install_bitwarden_unlock() {
  # The desktop login stores an unlock key. An active PC session may use it
  # without asking for the Bitwarden password again. A locked session may not.
  if [[ ! -f "$POLKIT_POLICY" ]]; then
    sudo tee "$POLKIT_POLICY" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1.0/policyconfig.dtd">
<policyconfig>
  <action id="com.bitwarden.Bitwarden.unlock">
    <description>Unlock Bitwarden</description>
    <message>Authenticate to unlock Bitwarden</message>
    <defaults>
      <allow_any>no</allow_any>
      <allow_inactive>no</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
  </action>
</policyconfig>
EOF
    sudo chown root:root "$POLKIT_POLICY"
  fi
  sudo tee "$POLKIT_RULE" >/dev/null <<'EOF'
polkit.addRule(function(action, subject) {
  if (action.id == "com.bitwarden.Bitwarden.unlock" && subject.active) {
    return polkit.Result.YES;
  }
});
EOF
  sudo chown root:root "$POLKIT_RULE"
  local desktop="/usr/share/applications/bitwarden.desktop"
  if [[ -f "$desktop" ]]; then
    mkdir -p "$HOME/.config/autostart"
    cp -a "$desktop" "$HOME/.config/autostart/bitwarden.desktop"
  fi
}

write_extension_policy() {
  local tmp
  if [[ -f "$POLICY_FILE" ]] && grep -q "$UBLOCK_ID" "$POLICY_FILE" && grep -q "$BITWARDEN_EXT_ID" "$POLICY_FILE" && grep -q "vault.bitwarden.eu" "$POLICY_FILE"; then
    say "extension policy already set"
    return
  fi
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
{
  "ExtensionInstallForcelist": [
    "${UBLOCK_ID};${UPDATE_URL}",
    "${BITWARDEN_EXT_ID};${UPDATE_URL}"
  ],
  "3rdparty": {
    "extensions": {
      "${BITWARDEN_EXT_ID}": {
        "environment": {
          "base": "https://vault.bitwarden.eu",
          "api": "https://api.bitwarden.eu",
          "identity": "https://identity.bitwarden.eu",
          "icons": "https://icons.bitwarden.eu",
          "notifications": "https://notifications.bitwarden.eu",
          "events": "https://events.bitwarden.eu",
          "webVault": "https://vault.bitwarden.eu"
        }
      }
    }
  }
}
EOF
  sudo install -d -m 0755 -o root -g root "$POLICY_DIR"
  sudo install -m 0644 -o root -g root -T "$tmp" "$POLICY_FILE"
  rm -f "$tmp"
  say "extension policy written"
}

apply_chromium_prefs() {
  python3 - "$PREFS" "$UBLOCK_ID" "$BITWARDEN_EXT_ID" <<'PY'
import json, os, sys
path, ublock, bitwarden = sys.argv[1:]
os.makedirs(os.path.dirname(path), exist_ok=True)
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        data = json.load(open(path))
    except Exception:
        data = {}

def nest(root, *keys):
    cur = root
    for key in keys:
        nxt = cur.get(key)
        if not isinstance(nxt, dict):
            nxt = {}
            cur[key] = nxt
        cur = nxt
    return cur

tabs = nest(data, "vertical_tabs")
tabs["enabled"] = True
tabs["enabled_first_time"] = True

hover = nest(data, "browser", "hovercard")
hover["memory_usage_enabled"] = False

bar = nest(data, "bookmark_bar")
bar["show_tab_groups"] = False

menu = nest(data, "everything_menu")
menu["pinned_to_tabstrip"] = False

ext = nest(data, "extensions")
pinned = ext.get("pinned_extensions")
if not isinstance(pinned, list):
    pinned = []
for extension_id in (ublock, bitwarden):
    if extension_id not in pinned:
        pinned.append(extension_id)
ext["pinned_extensions"] = pinned

toolbar = nest(data, "toolbar")
actions = toolbar.get("pinned_actions")
if not isinstance(actions, list):
    actions = []
for action in ("kActionDevTools", "kActionShowDownloads", "kActionQrCodeGenerator"):
    if action not in actions:
        actions.append(action)
toolbar["pinned_actions"] = actions

tmp = path + ".bootstrap"
with open(tmp, "w") as fh:
    json.dump(data, fh)
os.replace(tmp, path)
PY
  say "vertical tabs on, tab memory and tab-group buttons off"
  say "uBlock Origin Lite and Bitwarden pinned"
  say "toolbar: developer tools, downloads, QR code"
}

restore_bookmarks() {
  local have=0
  if [[ -f "$BOOKMARKS" ]]; then
    have=$(bookmark_count "$BOOKMARKS")
  fi
  if (( have > 0 )); then
    say "bookmarks already in the profile ($have)"
    return
  fi
  mkdir -p "$(dirname "$BOOKMARKS")"
  cp -a "$VAULT_BOOKMARKS" "$BOOKMARKS"
  say "bookmarks restored from Vault ($(bookmark_count "$BOOKMARKS"))"
}

wait_for_chromium_profile() {
  local _
  if [[ -f "$PREFS" ]]; then
    return 0
  fi
  say "Opening Chromium once so it creates its profile."
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- chromium --no-first-run about:blank >/dev/null 2>&1 &
  else
    chromium --no-first-run about:blank >/dev/null 2>&1 &
  fi
  for _ in $(seq 1 40); do
    [[ -f "$PREFS" ]] && break
    sleep 0.5
  done
  close_chromium
  [[ -f "$PREFS" ]]
}

set_keyboard

say "1. Dropbox"
if pkg_present dropbox; then
  say "Dropbox already installed"
else
  if ! command -v omarchy-install-service-dropbox >/dev/null 2>&1; then
    say "omarchy-install-service-dropbox is not on PATH. This script targets Omarchy 4.0.4."
    exit 1
  fi
  omarchy-install-service-dropbox
fi
start_dropbox
if dropbox_linked; then
  say "Dropbox already signed in"
else
  say "Sign in from the Dropbox icon in the top-right tray."
  say "The dropbox.com website does not connect this computer. Wait until ~/Dropbox appears."
  until dropbox_linked; do
    sleep 2
  done
  say "Dropbox is signed in"
fi
say "Waiting for Vault bookmarks."
until [[ -f "$VAULT_BOOKMARKS" ]]; do
  sleep 2
done
say "Vault bookmarks are here"

say "2. Bitwarden"
if pkg_present bitwarden bitwarden-cli; then
  say "Bitwarden already installed"
else
  omarchy-pkg-add bitwarden bitwarden-cli
fi
install_bitwarden_unlock
if bitwarden_app_logged_in; then
  say "Bitwarden already signed in"
else
  killall bitwarden 2>/dev/null || true
  set_bitwarden_eu
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- gtk-launch bitwarden >/dev/null 2>&1 &
  else
    gtk-launch bitwarden >/dev/null 2>&1 &
  fi
  say "Bitwarden is open on the EU server, vault.bitwarden.eu."
  say "Sign in once in that window. The script continues when the sign-in is saved."
  say "In that same window: Settings, Unlock with system authentication."
  say "This PC session is allowed to use that unlock, so it will not ask for the Bitwarden password again."
  until bitwarden_app_logged_in; do
    printf '  still waiting for the Bitwarden sign-in\n'
    sleep 5
  done
  say "Bitwarden is signed in"
fi

say "3. Chromium"
if pkg_present chromium; then
  say "Chromium already installed"
else
  omarchy-pkg-add chromium
fi
write_extension_policy
wait_for_chromium_profile || true
close_chromium
apply_chromium_prefs
restore_bookmarks
if command -v uwsm-app >/dev/null 2>&1; then
  uwsm-app -- chromium >/dev/null 2>&1 &
else
  chromium >/dev/null 2>&1 &
fi
say "Chromium is open with vertical tabs and bookmarks."
say "uBlock Origin Lite and the Bitwarden extension install from the policy."
say "The extension uses the Bitwarden app. Open it from the toolbar and choose Unlock with system authentication. It should not ask for the master password."
