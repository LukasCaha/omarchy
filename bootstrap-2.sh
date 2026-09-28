#!/usr/bin/env bash
# Barebones setup for Omarchy 4.0.4. Safe to re-run.
# 0. Czech QWERTZ, before any password
# 1. Dropbox service, then its own sign-in (the tray, not dropbox.com)
# 2. Bitwarden desktop, one sign-in, then the PC login unlocks it
# 3. Chromium bookmarks, vertical tabs, uBlock Origin Lite, Bitwarden extension
# 4. Vault sync: browser history and shell files copy when Chromium or bash exits
# 5. SSH config and public keys from the Vault, private keys from the Bitwarden agent
# 6. Desktop: inverted scroll, Catppuccin Latte, Geist, bar, screenshot folders
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

archive_excluded() {
  dropbox-cli exclude list 2>/dev/null | grep -q 'Dropbox/Archive'
}

set_nautilus_bookmarks() {
  # Omarchy sets the desktop directory to $HOME, so no Desktop folder exists.
  mkdir -p "$HOME/Desktop"
  xdg-user-dirs-update --set DESKTOP "$HOME/Desktop"
  local bookmarks="$HOME/.config/gtk-3.0/bookmarks"
  mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
  cat >"$bookmarks" <<EOF
file://$HOME/Desktop Desktop
file://$HOME/Projects Projects
file://$HOME/Downloads Downloads
file://$HOME/Dropbox/Resources Resources
file://$HOME/Dropbox/Screenshots Screenshots
file://$HOME/Dropbox/ScreenRecordings ScreenRecordings
file://$HOME/Dropbox Dropbox
EOF
  cp "$bookmarks" "$HOME/.config/gtk-4.0/bookmarks"
  local path icon
  while read -r path icon; do
    [[ -d "$path" ]] || continue
    gio set -t string "$path" metadata::custom-icon-name "$icon" >/dev/null
  done <<EOF
$HOME/Desktop user-desktop
$HOME/Projects org.gnome.Software.Develop
$HOME/Downloads folder-download
$HOME/Dropbox/Resources folder-documents
$HOME/Dropbox/Screenshots folder-pictures
$HOME/Dropbox/ScreenRecordings folder-videos
$HOME/Dropbox folder-dropbox
EOF
  say "Nautilus bookmarks are in the sidebar."
}

exclude_dropbox_archive() {
  if archive_excluded; then
    say "Dropbox/Archive stays online only"
    return 0
  fi
  say "Keeping ~/Dropbox/Archive online only. The cloud copy stays. This PC will not keep the files."
  local _
  for _ in $(seq 1 90); do
    if [[ -d "$HOME/Dropbox/Archive" ]]; then
      dropbox-cli exclude add "$HOME/Dropbox/Archive"
      say "Dropbox/Archive is excluded"
      return 0
    fi
    sleep 2
  done
  say "Archive has not appeared yet. When it does: dropbox exclude add ~/Dropbox/Archive"
}

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
  hyprctl keyword input:natural_scroll true >/dev/null || true
  hyprctl keyword input:touchpad:natural_scroll true >/dev/null || true
  mkdir -p "$(dirname "$INPUT_LUA")"
  if [[ ! -f "$INPUT_LUA" ]] || ! grep -q 'kb_layout = "cz"' "$INPUT_LUA"; then
    cat >>"$INPUT_LUA" <<'EOF'

-- Czech QWERTZ and inverted scroll. Written by bootstrap-2.sh.
hl.config({
  input = {
    kb_layout = "cz",
    kb_variant = "",
    kb_options = "compose:caps,shift:both_capslock_cancel",
    natural_scroll = true,
    touchpad = {
      natural_scroll = true,
    },
  },
})
EOF
  elif ! grep -q 'natural_scroll = true' "$INPUT_LUA"; then
    python3 - "$INPUT_LUA" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = 'kb_options = "compose:caps,shift:both_capslock_cancel",'
insert = needle + """
    natural_scroll = true,
    touchpad = {
      natural_scroll = true,
    },"""
if needle not in text:
    raise SystemExit("keyboard block not found")
path.write_text(text.replace(needle, insert, 1))
PY
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
  say "Scroll is inverted from the Omarchy default, for the mouse and the touchpad."
}

install_bar_helpers() {
  mkdir -p "$HOME/.local/bin" "$HOME/.config/omarchy/bar/modules"
  cat >"$HOME/.local/bin/cpu-temp-bar" <<'EOF'
#!/usr/bin/env python3
import glob
import os

cands = []
for path in sorted(glob.glob("/sys/class/hwmon/hwmon*/temp*_input")):
    base = os.path.dirname(path)
    key = os.path.basename(path)[: -len("_input")]
    label = ""
    label_path = os.path.join(base, key + "_label")
    if os.path.isfile(label_path):
        label = open(label_path).read().strip().lower()
    name = ""
    name_path = os.path.join(base, "name")
    if os.path.isfile(name_path):
        name = open(name_path).read().strip().lower()
    try:
        milli = int(open(path).read().strip())
    except Exception:
        continue
    if milli <= 0 or milli > 150000:
        continue
    blob = label + " " + name
    score = 0
    if any(part in blob for part in ("tctl", "package", "cpu", "k10temp", "coretemp", "zenpower")):
        score = 2
    elif "edge" in blob or "composite" in blob:
        score = 1
    cands.append((score, milli))
if not cands:
    raise SystemExit
cands.sort(key=lambda item: (-item[0], -item[1]))
print(f"\uf2c9 {cands[0][1] / 1000:.0f}°")
EOF
  cat >"$HOME/.local/bin/bar-clock" <<'EOF'
#!/usr/bin/env python3
import datetime
print(datetime.datetime.now().strftime("%A %H:%M:%S"), flush=True)
EOF
  cat >"$HOME/.local/bin/bar-battery-pct" <<'EOF'
#!/usr/bin/env python3
import glob
value = None
for path in sorted(glob.glob("/sys/class/power_supply/BAT*/capacity")):
    try:
        value = int(open(path).read().strip())
    except Exception:
        continue
if value is None:
    raise SystemExit
print(f"{value}%")
EOF
  chmod 755 "$HOME/.local/bin/cpu-temp-bar" "$HOME/.local/bin/bar-clock" "$HOME/.local/bin/bar-battery-pct"
  cat >"$HOME/.config/omarchy/bar/modules/tray-always.qml" <<'EOF'
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Services.SystemTray

Item {
  id: root
  property var bar
  property string moduleName
  property var settings

  function keep(item) {
    if (!item || item.status === Status.Passive) return false
    var blob = (String(item.id || "") + " " + String(item.title || "") + " " + String(item.tooltipTitle || "")).toLowerCase()
    if (blob.indexOf("localsend") !== -1) return false
    if (blob.indexOf("dropbox") !== -1) return false
    return true
  }

  property var trayItems: []
  implicitWidth: Math.max(1, row.implicitWidth)
  implicitHeight: bar ? bar.barSize : 26

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var values = SystemTray.items ? SystemTray.items.values : []
      var next = []
      for (var i = 0; i < values.length; i++) next.push(values[i])
      root.trayItems = next
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 0

    Repeater {
      model: root.trayItems
      delegate: Item {
        id: slot
        required property var modelData
        visible: root.keep(modelData)
        implicitWidth: visible ? 27 : 0
        implicitHeight: 27

        Image {
          id: icon
          readonly property bool symbolic: String(slot.modelData.icon || "").split("?")[0].slice(-9) === "-symbolic"
          anchors.centerIn: parent
          width: 12
          height: 12
          fillMode: Image.PreserveAspectFit
          sourceSize.width: Math.round(width * Screen.devicePixelRatio)
          sourceSize.height: Math.round(height * Screen.devicePixelRatio)
          source: String(slot.modelData.icon || "")
          visible: !symbolic
          layer.enabled: symbolic
        }

        MultiEffect {
          anchors.fill: icon
          source: icon
          visible: icon.symbolic
          colorization: 1.0
          colorizationColor: root.bar ? root.bar.foreground : "white"
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: if (root.bar) root.bar.showTooltip(slot, slot.modelData.tooltipTitle || slot.modelData.title || "")
          onExited: if (root.bar) root.bar.hideTooltip(slot)
          onClicked: function(mouse) {
            if (mouse.button === Qt.MiddleButton) slot.modelData.secondaryActivate()
            else if (mouse.button === Qt.RightButton && slot.modelData.onlyMenu) slot.modelData.activate()
            else slot.modelData.activate()
          }
          onWheel: function(wheel) {
            slot.modelData.scroll(wheel.angleDelta.y, false)
          }
        }
      }
    }
  }
}
EOF
}

configure_bar() {
  local cfg="$HOME/.config/omarchy/shell.json"
  local defaults="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
  local src="$defaults"
  [[ -s "$cfg" ]] && src="$cfg"
  mkdir -p "$(dirname "$cfg")"
  python3 - "$src" "$cfg" "$HOME/.local/bin/bar-clock" "$HOME/.local/bin/cpu-temp-bar" "$HOME/.local/bin/bar-battery-pct" <<'PY'
import json, sys
src, dest, clock_exec, temp_exec, battery_exec = sys.argv[1:]
with open(src) as fh:
    data = json.load(fh)
data["version"] = 1
bar = data.setdefault("bar", {})
bar["transparent"] = True
layout = bar.setdefault("layout", {})
for section in ("left", "center", "right"):
    layout.setdefault(section, [])

def entries(section):
    out = []
    for entry in layout.get(section) or []:
        if isinstance(entry, str):
            entry = {"id": entry}
        if isinstance(entry, dict):
            out.append(entry)
    return out

center = []
clock_placed = False
indicators_seen = False
clock = {
    "id": "clock-live",
    "type": "command",
    "exec": clock_exec,
    "interval": 1,
    "fontSize": 13,
}
for entry in entries("center"):
    widget_id = entry.get("id")
    if widget_id == "omarchy.indicators":
        entry["alwaysShow"] = True
        indicators_seen = True
        center.append(entry)
        continue
    if widget_id in ("omarchy.clock", "clock-live"):
        if not clock_placed:
            center.append(clock)
            clock_placed = True
        continue
    center.append(entry)
if not indicators_seen:
    center.insert(0, {"id": "omarchy.indicators", "alwaysShow": True})
if not clock_placed:
    center.append(clock)
layout["center"] = center
bar["centerAnchor"] = "clock-live"

temp = {
    "id": "cpu-temp",
    "type": "command",
    "exec": temp_exec,
    "interval": 1,
    "fontSize": 13,
    "horizontalMargin": 4,
    "tooltip": "CPU temperature",
    "onClick": "omarchy-launch-or-focus-tui btop",
}
battery = {
    "id": "battery-pct",
    "type": "command",
    "exec": battery_exec,
    "interval": 1,
    "fontSize": 13,
    "horizontalMargin": 2,
    "tooltip": "Battery",
}
right = []
for entry in entries("right"):
    widget_id = entry.get("id")
    if widget_id in ("omarchy.tray", "tray-always", "cpu-temp", "battery-pct"):
        continue
    if widget_id == "omarchy.power":
        entry["showPercentage"] = False
    right.append(entry)
if not any(entry.get("id") == "omarchy.power" for entry in right):
    right.append({"id": "omarchy.power", "showPercentage": False})
right.insert(0, {"id": "tray-always", "type": "qml"})
power_at = next(i for i, entry in enumerate(right) if entry.get("id") == "omarchy.power")
right.insert(power_at, temp)
right.insert(power_at + 2, battery)
layout["right"] = right

tmp = dest + ".bootstrap"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace = __import__("os").replace
os.replace(tmp, dest)
PY
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell reloadConfig >/dev/null 2>&1 || omarchy-restart-shell >/dev/null 2>&1 || true
  fi
}

set_latte_second_wallpaper() {
  local theme_dir="${OMARCHY_PATH:-/usr/share/omarchy}/themes/catppuccin-latte/backgrounds"
  local -a backgrounds=()
  local bg
  mapfile -d '' backgrounds < <(
    find -L "$theme_dir" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) \
      -print0 2>/dev/null | sort -z
  )
  if (( ${#backgrounds[@]} < 2 )); then
    say "Catppuccin Latte has no second wallpaper."
    return 0
  fi
  bg="${backgrounds[1]}"
  omarchy theme bg set "$bg"
  say "Wallpaper: ${bg##*/}"
}

set_desktop() {
  say "Theme: Catppuccin Latte"
  omarchy theme set "Catppuccin Latte"
  set_latte_second_wallpaper
  if ! fc-list : family | grep -Fqi "GeistMono Nerd Font"; then
    omarchy-pkg-add otf-geist-mono-nerd
  fi
  say "Font: Geist Mono"
  omarchy font set "GeistMono Nerd Font"
  install_bar_helpers
  configure_bar
  mkdir -p "$HOME/Dropbox/Screenshots" "$HOME/Dropbox/ScreenRecordings"
  mkdir -p "$HOME/.config/uwsm/env.d"
  cat >"$HOME/.config/uwsm/env.d/capture" <<EOF
export OMARCHY_SCREENSHOT_DIR="\$HOME/Dropbox/Screenshots"
export OMARCHY_SCREENRECORD_DIR="\$HOME/Dropbox/ScreenRecordings"
EOF
  say "Bar is transparent. Tray icons stay open. The clock and CPU temperature update every second."
  say "CPU temperature sits left of the battery and opens btop. The battery percent sits to the right of the battery icon."
  say "Screenshots go to ~/Dropbox/Screenshots and recordings to ~/Dropbox/ScreenRecordings after the next login."
  set_nautilus_bookmarks
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

cache_bookmark_favicons() {
  [[ -f "$BOOKMARKS" ]] || return 0
  python3 - "$BOOKMARKS" "$HOME/.config/chromium/Default/Favicons" <<'PY'
import json, os, re, sqlite3, struct, time, urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

bookmarks_path, db_path = __import__("sys").argv[1:]

def walk(node, found):
    if not isinstance(node, dict):
        return
    if node.get("type") == "url" and isinstance(node.get("url"), str):
        found.append(node["url"])
    for child in node.get("children") or []:
        walk(child, found)

try:
    roots = json.load(open(bookmarks_path)).get("roots") or {}
except Exception:
    raise SystemExit(0)
urls = []
for root in roots.values():
    walk(root, urls)
pages = []
seen = set()
for url in urls:
    if url in seen or not url.startswith(("http://", "https://")):
        continue
    seen.add(url)
    pages.append(url)
if not pages:
    raise SystemExit(0)

os.makedirs(os.path.dirname(db_path), exist_ok=True)
db = sqlite3.connect(db_path)
db.executescript("""
CREATE TABLE IF NOT EXISTS meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
CREATE TABLE IF NOT EXISTS icon_mapping(id INTEGER PRIMARY KEY, page_url LONGVARCHAR NOT NULL, icon_id INTEGER, page_url_type INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS favicons(id INTEGER PRIMARY KEY, url LONGVARCHAR NOT NULL, icon_type INTEGER DEFAULT 1);
CREATE TABLE IF NOT EXISTS favicon_bitmaps(id INTEGER PRIMARY KEY, icon_id INTEGER NOT NULL, last_updated INTEGER DEFAULT 0, image_data BLOB, width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, last_requested INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS icon_mapping_page_url_idx ON icon_mapping(page_url);
CREATE INDEX IF NOT EXISTS icon_mapping_icon_id_idx ON icon_mapping(icon_id);
CREATE INDEX IF NOT EXISTS favicons_url ON favicons(url);
CREATE INDEX IF NOT EXISTS favicon_bitmaps_icon_id ON favicon_bitmaps(icon_id);
""")
db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES ('version', '9')")
db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES ('last_compatible_version', '9')")
db.execute("INSERT OR IGNORE INTO meta(key, value) VALUES ('mmap_status', '-1')")

def chrome_now():
    return int((time.time() + 11644473600) * 1_000_000)

def looks_like_image(blob):
    if not blob or len(blob) < 8 or len(blob) > 500_000:
        return False
    return (
        blob.startswith(b"\x89PNG\r\n\x1a\n")
        or blob.startswith(b"\x00\x00\x01\x00")
        or blob.startswith(b"\xff\xd8")
        or blob.startswith(b"GIF8")
        or (blob.startswith(b"RIFF") and blob[8:12] == b"WEBP")
    )

def looks_like_svg(blob):
    head = blob[:300].lstrip().lower()
    return b"<svg" in head or head.startswith(b"<?xml")

def image_size(blob):
    if blob.startswith(b"\x89PNG\r\n\x1a\n") and len(blob) >= 24:
        width, height = struct.unpack(">II", blob[16:24])
        return int(width), int(height)
    return 0, 0

def svg_to_png(blob):
    import shutil, subprocess
    tool = shutil.which("rsvg-convert")
    if tool:
        proc = subprocess.run(
            [tool, "-w", "32", "-h", "32", "-f", "png"],
            input=blob, capture_output=True,
        )
        if proc.returncode == 0 and looks_like_image(proc.stdout):
            return proc.stdout
    tool = shutil.which("magick") or shutil.which("convert")
    if not tool:
        return None
    proc = subprocess.run(
        [tool, "-background", "none", "-resize", "32x32", "svg:-", "png:-"],
        input=blob, capture_output=True,
    )
    if proc.returncode == 0 and looks_like_image(proc.stdout):
        return proc.stdout
    return None

def fetch(url):
    request = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "text/html,image/png,image/x-icon,image/svg+xml,*/*;q=0.8",
    })
    with urllib.request.urlopen(request, timeout=12) as response:
        return response.read(400_000), response.geturl()

def attr(tag, name):
    match = re.search(rf"\b{name}\s*=\s*('([^']*)'|\"([^\"]*)\"|([^\s>]+))", tag, re.I)
    if not match:
        return ""
    return next(group for group in match.groups()[1:] if group is not None)

def color_scheme(media):
    text = (media or "").lower().replace(" ", "")
    if "prefers-color-scheme:dark" in text:
        return "dark"
    if "prefers-color-scheme:light" in text:
        return "light"
    return "default"

def size_rank(sizes):
    best = 80
    for part in (sizes or "").lower().replace(" ", "").split(","):
        if part in ("", "any"):
            best = min(best, 12)
            continue
        match = re.match(r"(\d+)x(\d+)", part)
        if not match:
            continue
        edge = max(int(match.group(1)), int(match.group(2)))
        best = min(best, abs(edge - 32))
    return best

def icon_for(page_url):
    parts = urllib.parse.urlsplit(page_url)
    origin = f"{parts.scheme}://{parts.netloc}"
    candidates = []
    final_page = page_url
    try:
        html, final_page = fetch(page_url)
        text = html[:200_000].decode("utf-8", "ignore")
        for tag in re.findall(r"<link\b[^>]*>", text, re.I):
            rel = attr(tag, "rel").lower()
            if "icon" not in rel or "mask-icon" in rel:
                continue
            href = attr(tag, "href")
            if not href:
                continue
            kind = "apple" if "apple-touch" in rel else "icon"
            candidates.append({
                "url": urllib.parse.urljoin(final_page, href),
                "scheme": color_scheme(attr(tag, "media")),
                "kind": kind,
                "size": size_rank(attr(tag, "sizes")),
                "type": attr(tag, "type").lower(),
            })
    except Exception:
        pass
    if any(item["scheme"] != "dark" for item in candidates):
        candidates = [item for item in candidates if item["scheme"] != "dark"]
    scheme_rank = {"default": 0, "light": 1, "dark": 2}
    def sort_key(item):
        svg = "svg" in item["type"] or item["url"].lower().split("?")[0].endswith(".svg")
        return (
            scheme_rank[item["scheme"]],
            0 if item["kind"] == "icon" else 1,
            1 if svg else 0,
            item["size"],
        )
    candidates.sort(key=sort_key)
    ordered = []
    seen_urls = set()
    for item in candidates:
        if item["url"] not in seen_urls:
            seen_urls.add(item["url"])
            ordered.append(item["url"])
    ordered.append(origin + "/favicon.ico")
    for icon_url in ordered:
        if icon_url.startswith("data:"):
            import base64
            header, _, payload = icon_url.partition(",")
            if ";base64" not in header:
                continue
            try:
                blob, final_icon = base64.b64decode(payload), icon_url[:80]
            except Exception:
                continue
        else:
            try:
                blob, final_icon = fetch(icon_url)
            except Exception:
                continue
        if looks_like_svg(blob):
            blob = svg_to_png(blob)
            if not blob:
                continue
            final_icon = icon_url + "#png"
        if looks_like_image(blob):
            return final_icon, blob
    return None

found = {}
missed = 0
with ThreadPoolExecutor(max_workers=6) as pool:
    futures = {pool.submit(icon_for, page): page for page in pages}
    for future in as_completed(futures):
        page = futures[future]
        try:
            result = future.result()
        except Exception:
            result = None
        if result:
            found[page] = result
        else:
            missed += 1

now = chrome_now()
stored = 0
icon_ids = {}
for page, (icon_url, blob) in found.items():
    db.execute("DELETE FROM icon_mapping WHERE page_url = ?", (page,))
    icon_id = icon_ids.get(icon_url)
    if icon_id is None:
        row = db.execute("SELECT id FROM favicons WHERE url = ?", (icon_url,)).fetchone()
        if row:
            icon_id = row[0]
            db.execute("DELETE FROM favicon_bitmaps WHERE icon_id = ?", (icon_id,))
        else:
            cur = db.execute(
                "INSERT INTO favicons(url, icon_type) VALUES (?, 1)",
                (icon_url,),
            )
            icon_id = cur.lastrowid
        width, height = image_size(blob)
        db.execute(
            "INSERT INTO favicon_bitmaps(icon_id, last_updated, image_data, width, height, last_requested) VALUES (?, ?, ?, ?, ?, ?)",
            (icon_id, now, blob, width, height, now),
        )
        icon_ids[icon_url] = icon_id
    db.execute(
        "INSERT INTO icon_mapping(page_url, icon_id, page_url_type) VALUES (?, ?, 0)",
        (page, icon_id),
    )
    stored += 1
db.commit()
print(f"cached {stored} bookmark favicons, {missed} still missing")
PY
}

enable_bitwarden_ssh_agent() {
  python3 - "$HOME/.config/Bitwarden/data.json" <<'PY'
import json, os, sys
path = sys.argv[1]
if not os.path.exists(path):
    raise SystemExit(1)
data = json.load(open(path))
data["global_desktopSettings_sshAgentEnabled"] = True
# Local to this computer. Not part of the synced Bitwarden account.
# Older builds use the tray keys. Newer builds use runInBackground.
data["global_desktopSettings_trayEnabled"] = True
data["global_desktopSettings_startToTray"] = True
data["global_desktopSettings_minimizeToTray"] = True
data["global_desktopSettings_closeToTray"] = True
data["global_desktopSettings_openAtLogin"] = True
data["global_desktopSettings_runInBackground"] = True
active = data.get("global_account_activeAccountId")
if isinstance(active, str) and len(active) > 8:
    data[f"{active}_desktopSettings_sshAgentRememberAuthorizations"] = "never"
    data[f"{active}_vaultTimeoutSettings_vaultTimeout"] = "never"
    data[f"{active}_vaultTimeoutSettings_vaultTimeoutAction"] = "lock"
    data[f"{active}_biometricSettings_biometricUnlockEnabled"] = True
    data[f"{active}_biometricSettings_promptAutomatically"] = True
tmp = path + ".bootstrap"
with open(tmp, "w") as fh:
    json.dump(data, fh)
os.replace(tmp, path)
PY
}

install_ssh() {
  local vault="$HOME/Dropbox/Vault/ssh"
  local name src dst mode
  mkdir -p "$HOME/.ssh" "$vault"
  chmod 700 "$HOME/.ssh"
  # Public files only. Private keys stay inside Bitwarden.
  for name in config known_hosts id_ed25519.pub id_ed25519_vps.pub; do
    src="$HOME/.ssh/$name"
    dst="$vault/$name"
    if [[ "$name" == *.pub ]]; then
      mode=644
    else
      mode=600
    fi
    if [[ -f "$src" && ! -f "$dst" ]]; then
      install -m "$mode" "$src" "$dst"
    elif [[ -f "$dst" && ! -f "$src" ]]; then
      install -m "$mode" "$dst" "$src"
    fi
  done
  # Quit first. A running Bitwarden writes its old settings over data.json on exit.
  if pgrep -x bitwarden >/dev/null 2>&1; then
    killall bitwarden 2>/dev/null || true
    local _
    for _ in $(seq 1 20); do
      pgrep -x bitwarden >/dev/null 2>&1 || break
      sleep 0.5
    done
  fi
  if enable_bitwarden_ssh_agent; then
    if command -v uwsm-app >/dev/null 2>&1; then
      uwsm-app -- gtk-launch bitwarden >/dev/null 2>&1 &
    else
      gtk-launch bitwarden >/dev/null 2>&1 &
    fi
    local _
    for _ in $(seq 1 30); do
      [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]] && break
      sleep 0.5
    done
  fi
  say "SSH config and public keys are in ~/.ssh."
  say "Bitwarden SSH agent is on, and it will not ask before each connection."
  say "Vault timeout is Never and the timeout action is Lock, with unlock by system authentication."
  say "The browser extension keeps its own login. Sign in there once, set the same timeout, and turn on Share unlock with Desktop."
  say "Those keys have to be stored in Bitwarden as SSH keys. A secure note is not used."
  if [[ -S "$HOME/.bitwarden-ssh-agent.sock" ]]; then
    say "The Bitwarden SSH agent is listening."
  else
    say "The agent socket is not up yet. It appears after Bitwarden unlocks."
  fi
}

install_vault_sync() {
  local dir src unit fetched
  src=""
  fetched=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    dir=$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    if [[ -f "$dir/vault-sync" ]]; then
      src="$dir/vault-sync"
    fi
  fi
  # curl | sh has no script path, so the helper is not sitting next to it.
  if [[ -z "$src" ]]; then
    fetched=$(mktemp)
    src="$fetched"
    curl -fsSL "https://raw.githubusercontent.com/LukasCaha/omarchy/main/vault-sync" -o "$src"
  fi
  mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user" "$HOME/Dropbox/Vault/shell"
  install -m 0755 "$src" "$HOME/.local/bin/vault-sync"
  [[ -n "$fetched" ]] && rm -f "$fetched"
  if [[ ! -f "$HOME/.bashrc" ]]; then
    if [[ -f "$HOME/.local/share/omarchy/default/bashrc" ]]; then
      cp "$HOME/.local/share/omarchy/default/bashrc" "$HOME/.bashrc"
    elif [[ -f /usr/share/omarchy/default/bashrc ]]; then
      cp /usr/share/omarchy/default/bashrc "$HOME/.bashrc"
    fi
  fi
  if [[ -f "$HOME/.bashrc" ]] && ! grep -q 'vault-sync:start' "$HOME/.bashrc"; then
    python3 - "$HOME/.bashrc" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
hook = """
# vault-sync:start
if [[ -z ${VAULT_SYNC_REEXEC:-} && -x "$HOME/.local/bin/vault-sync" ]]; then
  if "$HOME/.local/bin/vault-sync" shell-startup; then
    export VAULT_SYNC_REEXEC=1
    exec bash
  fi
fi
# vault-sync:end
"""
marker = "[[ $- != *i* ]] && return\n"
if marker in text:
    text = text.replace(marker, marker + hook, 1)
else:
    text = hook + text
if "vault-sync\" push shell" not in text:
    text += """
# vault-sync:start
[[ -x "$HOME/.local/bin/vault-sync" ]] && trap 'history -a; "$HOME/.local/bin/vault-sync" push shell' EXIT
# vault-sync:end
"""
path.write_text(text)
PY
  fi
  unit="$HOME/.config/systemd/user/vault-sync.service"
  cat >"$unit" <<'EOF'
[Unit]
Description=Copy Chromium history into Dropbox when Chromium exits

[Service]
ExecStart=%h/.local/bin/vault-sync watch-chromium
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
  say "Vault sync is installed."
  say "History and Shortcuts copy into Dropbox when Chromium quits."
  say "Shell config and bash history copy into Dropbox when a terminal exits."
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
exclude_dropbox_archive
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
say "Caching bookmark favicons."
cache_bookmark_favicons || say "bookmark favicons could not be cached"
say "4. Vault sync"
install_vault_sync
"$HOME/.local/bin/vault-sync" reconcile
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload
  systemctl --user enable --now vault-sync.service
fi
if command -v uwsm-app >/dev/null 2>&1; then
  uwsm-app -- chromium >/dev/null 2>&1 &
else
  chromium >/dev/null 2>&1 &
fi
say "Chromium is open with vertical tabs and bookmarks."
say "uBlock Origin Lite and the Bitwarden extension install from the policy."

say "5. SSH"
install_ssh

say "6. Desktop"
set_desktop

say ""
say "Still to do by hand:"
say "1. In the Bitwarden app: Settings, Unlock with system authentication. The script records the setting. The unlock key is created only when that box is checked."
say "2. In the Chromium Bitwarden extension: sign in once, to the same EU account."
say "3. Extension Settings, Account security: Share unlock with Desktop. If that line is missing, Unlock with biometrics."
say "4. In the extension, Timeout Never and Timeout action Lock, if those controls are still shown and not managed by the desktop app."
