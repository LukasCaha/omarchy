#!/usr/bin/env bash
# Barebones setup for Omarchy 4.0.4. Safe to re-run.
# 0. Czech QWERTZ, before any password
# 1. Dropbox service, then its own sign-in (the tray, not dropbox.com)
# 2. Bitwarden desktop, one sign-in, then the PC login unlocks it
# 3. Chromium bookmarks, vertical tabs, uBlock Origin Lite, Bitwarden extension
# 4. Vault sync: browser history and shell files copy when Chromium or bash exits
# 5. SSH config and public keys from the Vault, private keys from the Bitwarden agent
# 6. Desktop: inverted scroll, Catppuccin Latte, Geist, bar, screenshot folders
# 7. Work apps: SAM CLI, Obsidian Notes on the shelf, qBittorrent, and the rest
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
  hyprctl keyword input:natural_scroll false >/dev/null || true
  hyprctl keyword input:touchpad:natural_scroll true >/dev/null || true
  mkdir -p "$(dirname "$INPUT_LUA")"
  if [[ ! -f "$INPUT_LUA" ]] || ! grep -q 'kb_layout = "cz"' "$INPUT_LUA"; then
    cat >>"$INPUT_LUA" <<'EOF'

-- Czech QWERTZ. Mouse follows the wheel. Touchpad scroll is reversed.
-- Written by bootstrap-2.sh.
hl.config({
  input = {
    kb_layout = "cz",
    kb_variant = "",
    kb_options = "compose:caps,shift:both_capslock_cancel",
    natural_scroll = false,
    touchpad = {
      natural_scroll = true,
    },
  },
})
EOF
  fi
  python3 - "$INPUT_LUA" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
old = """    touchpad = {
      natural_scroll = false,
    },"""
new = """    touchpad = {
      natural_scroll = true,
    },"""
if old in text:
    text = text.replace(old, new, 1)
elif "touchpad" not in text:
    needle = 'kb_options = "compose:caps,shift:both_capslock_cancel",'
    insert = needle + """
    natural_scroll = false,
""" + new
    if needle not in text:
        raise SystemExit("keyboard block not found")
    text = text.replace(needle, insert, 1)
path.write_text(text)
PY
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
  hyprctl reload >/dev/null || true
  say "Czech QWERTZ is on. Type passwords with that layout."
  say "Scroll follows the wheel: down moves the page down."
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
import json, os, sys
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

set_capture_dirs() {
  mkdir -p "$HOME/Dropbox/Screenshots" "$HOME/Dropbox/ScreenRecordings"
  mkdir -p "$HOME/.config/uwsm/env.d"
  cat >"$HOME/.config/uwsm/env.d/capture" <<EOF
export OMARCHY_SCREENSHOT_DIR="\$HOME/Dropbox/Screenshots"
export OMARCHY_SCREENRECORD_DIR="\$HOME/Dropbox/ScreenRecordings"
EOF
  local hypr="$HOME/.config/hypr/hyprland.lua"
  if [[ -f "$hypr" ]] && ! grep -q "bootstrap-2 capture dirs" "$hypr"; then
    cat >>"$hypr" <<'EOF'

-- bootstrap-2 capture dirs
hl.env("OMARCHY_SCREENSHOT_DIR", (os.getenv("HOME") or "") .. "/Dropbox/Screenshots")
hl.env("OMARCHY_SCREENRECORD_DIR", (os.getenv("HOME") or "") .. "/Dropbox/ScreenRecordings")
EOF
  fi
  hyprctl keyword env OMARCHY_SCREENSHOT_DIR,"$HOME/Dropbox/Screenshots" >/dev/null || true
  hyprctl keyword env OMARCHY_SCREENRECORD_DIR,"$HOME/Dropbox/ScreenRecordings" >/dev/null || true
  hyprctl reload >/dev/null || true
  say "Screenshots go to ~/Dropbox/Screenshots and recordings to ~/Dropbox/ScreenRecordings."
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
  set_capture_dirs
  set_nautilus_bookmarks
  install_bar_helpers
  configure_bar
  say "Bar is transparent. Tray icons stay open. The clock and CPU temperature update every second."
  say "CPU temperature sits left of the battery and opens btop. The battery percent sits to the right of the battery icon."
}

install_repo_pkgs() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    if pkg_present "$pkg"; then
      continue
    fi
    if ! pacman -Si "$pkg" &>/dev/null; then
      say "Package $pkg is not in the Omarchy repositories."
      continue
    fi
    missing+=("$pkg")
  done
  if ((${#missing[@]})); then
    omarchy-pkg-add "${missing[@]}"
  fi
}

install_aur_pkgs() {
  local pkg
  if ! command -v omarchy-pkg-aur-add >/dev/null 2>&1; then
    say "omarchy-pkg-aur-add is missing, so the AUR apps were not installed."
    return 1
  fi
  for pkg in "$@"; do
    if pkg_present "$pkg"; then
      continue
    fi
    omarchy-pkg-aur-add "$pkg" || say "Could not install $pkg."
  done
}

install_work_apps() {
  # Official repositories. omarchy-pkg-add only calls pacman.
  install_repo_pkgs aws-cli github-cli vlc gimp qbittorrent obsidian python-secretstorage python-yaml
  if ! pkg_present yaak; then
    if pacman -Si yaak &>/dev/null; then
      omarchy-pkg-add yaak
    else
      install_aur_pkgs yaak-bin
    fi
  fi
  # AUR. These names are not in pacman, which is why a single omarchy-pkg-add failed.
  install_aur_pkgs aws-sam-cli-bin grok-bot-bin fastpotify-bin
  install_tableplus
  install_cursor_agent
  say "Work apps are installed."
}

install_tableplus() {
  if pkg_present tableplus; then
    say "TablePlus is already installed."
    return 0
  fi
  # The AUR PKGBUILD downloads tableplus_0.1.314_amd64.deb. TablePlus has
  # removed that file, so yay stops at 404. Build the same package with the
  # deb that is still in the pool.
  say "Building TablePlus from the AUR package against the current deb."
  install_repo_pkgs gtksourceview3 libgee gnome-keyring base-devel
  local pool suffix sumline page deb ver url work sum
  case "$(uname -m)" in
    aarch64|arm64)
      pool="https://deb.tableplus.com/debian/24-arm/pool/main/t/tableplus/"
      suffix="arm64"
      sumline="sha256sums_aarch64"
      ;;
    *)
      pool="https://deb.tableplus.com/debian/24/pool/main/t/tableplus/"
      suffix="amd64"
      sumline="sha256sums_x86_64"
      ;;
  esac
  page=$(curl -fsSL "$pool")
  deb=$(printf '%s\n' "$page" | grep -oE "tableplus_[0-9.]+_${suffix}\\.deb" | sort -V | tail -1)
  if [[ -z "$deb" ]]; then
    say "TablePlus deb was not found."
    return 0
  fi
  ver=${deb#tableplus_}
  ver=${ver%_${suffix}.deb}
  url="${pool}${deb}"
  work=$(mktemp -d)
  git clone --depth 1 https://aur.archlinux.org/tableplus.git "$work/tableplus"
  curl -fsSL -o "$work/tableplus.deb" "$url"
  sum=$(sha256sum "$work/tableplus.deb" | awk '{print $1}')
  rm -f "$work/tableplus.deb"
  python3 - "$work/tableplus/PKGBUILD" "$ver" "$suffix" "$sumline" "$sum" "$url" <<'PY'
import pathlib, sys
path, ver, suffix, sumline, digest, url = sys.argv[1:]
lines = pathlib.Path(path).read_text().splitlines()
out = []
for line in lines:
    if line.startswith("pkgver="):
        line = f"pkgver={ver}"
    elif line.startswith(f"source_{'aarch64' if suffix == 'arm64' else 'x86_64'}="):
        line = f"source_{'aarch64' if suffix == 'arm64' else 'x86_64'}=(\"{url}\")"
    elif line.startswith(f"{sumline}="):
        line = f"{sumline}=('{digest}')"
    out.append(line)
pathlib.Path(path).write_text("\n".join(out) + "\n")
PY
  if ! (cd "$work/tableplus" && makepkg -si --noconfirm); then
    rm -rf "$work"
    say "TablePlus did not build."
    return 0
  fi
  rm -rf "$work"
  say "TablePlus is installed from the AUR package, using ${deb}."
}

apply_local_domains() {
  local sites="$HOME/.config/domains/sites"
  if [[ ! -f "$sites" ]]; then
    say "No domain list at ~/.config/domains/sites yet."
    return 0
  fi
  install_repo_pkgs dnsmasq gum
  python3 - "$sites" <<'PY'
import pathlib, sys
sites = pathlib.Path(sys.argv[1]).read_text().splitlines()
rows = []
for line in sites:
    if not line.strip() or line.startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) < 2:
        continue
    name, ip = parts[0].strip(), parts[1].strip()
    if name and ip:
        rows.append(f"{ip}  {name}")
hosts = pathlib.Path("/etc/hosts")
text = hosts.read_text() if hosts.exists() else ""
begin, end = "# BEGIN domains", "# END domains"
block = begin + "\n" + "\n".join(rows) + "\n" + end + "\n"
if begin in text and end in text:
    pre, rest = text.split(begin, 1)
    _, post = rest.split(end, 1)
    text = pre.rstrip() + "\n\n" + block + post.lstrip("\n")
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text = text.rstrip() + "\n\n" + block
tmp = pathlib.Path("/tmp/bootstrap-hosts")
tmp.write_text(text)
PY
  sudo cp /tmp/bootstrap-hosts /etc/hosts
  sudo chmod 644 /etc/hosts
  rm -f /tmp/bootstrap-hosts
  local conf="/etc/dnsmasq.conf"
  if [[ -f "$conf" ]] && ! grep -q '^address=/\.test/127\.0\.0\.1$' "$conf"; then
    printf '\naddress=/.test/127.0.0.1\n' | sudo tee -a "$conf" >/dev/null
  fi
  if [[ -f "$conf" ]] && ! grep -q '^listen-address=127\.0\.0\.1$' "$conf"; then
    printf 'listen-address=127.0.0.1\n' | sudo tee -a "$conf" >/dev/null
  fi
  if [[ -f "$conf" ]] && ! grep -q '^server=1\.1\.1\.1$' "$conf"; then
    printf 'server=8.8.8.8\nserver=1.1.1.1\n' | sudo tee -a "$conf" >/dev/null
  fi
  if [[ ! -f /etc/resolv.conf ]] || ! grep -q '^nameserver 127\.0\.0\.1$' /etc/resolv.conf; then
    printf 'nameserver 127.0.0.1\n' | sudo tee /etc/resolv.conf >/dev/null
  fi
  sudo systemctl enable --now dnsmasq >/dev/null 2>&1 || true
  sudo systemctl reload dnsmasq >/dev/null 2>&1 || sudo systemctl restart dnsmasq >/dev/null 2>&1 || true
  say "Local domains from ~/.config/domains/sites are in /etc/hosts. *.test points at 127.0.0.1."
}

sync_wifi_credentials() {
  local vault="$HOME/Dropbox/Vault/wifi"
  local src="/etc/NetworkManager/system-connections"
  local iwd="/var/lib/iwd"
  local f base
  mkdir -p "$vault/iwd" || sudo mkdir -p "$vault/iwd"
  chmod 700 "$vault" 2>/dev/null || true
  if ! sudo -v; then
    say "Wi-Fi passwords were not copied. sudo is required."
    return 0
  fi
  if [[ -d "$src" ]]; then
    shopt -s nullglob
    for f in "$src"/*; do
      if sudo grep -q '^type=wifi$' "$f"; then
        base="$(basename "$f")"
        sudo cp -a "$f" "$vault/$base"
        sudo chown "$USER:$USER" "$vault/$base"
        chmod 600 "$vault/$base"
      fi
    done
    shopt -u nullglob
  fi
  sudo python3 - "$iwd" "$vault" <<'PY'
import os, pathlib, re, shutil, sys, uuid
iwd, vault = map(pathlib.Path, sys.argv[1:])
store = vault / "iwd"
store.mkdir(parents=True, exist_ok=True)
if not iwd.is_dir():
    sys.exit(0)
for src in iwd.glob("*.psk"):
    dst = store / src.name
    shutil.copyfile(src, dst)
    os.chown(dst, os.getuid(), os.getgid())
    os.chmod(dst, 0o600)
    text = src.read_text(errors="replace")
    phrase = re.search(r"^Passphrase=(.*)$", text, re.M)
    key = re.search(r"^PreSharedKey=([0-9a-fA-F]{64})$", text, re.M)
    secret = phrase.group(1) if phrase else (key.group(1) if key else "")
    if not secret:
        continue
    raw = src.name[:-4]
    ssid = bytes.fromhex(raw[1:]).decode("utf-8", "replace") if raw.startswith("=") else raw
    out = vault / (ssid + ".nmconnection")
    if out.exists() and "psk=" in out.read_text(errors="replace"):
        existing = out.read_text(errors="replace")
        current = re.search(r"^psk=(.*)$", existing, re.M)
        if current and not re.fullmatch(r"[0-9a-fA-F]{64}", current.group(1)):
            continue
    profile = "\n".join([
        "[connection]",
        f"id={ssid}",
        f"uuid={uuid.uuid5(uuid.NAMESPACE_DNS, 'wifi:' + ssid)}",
        "type=wifi",
        "",
        "[wifi]",
        "mode=infrastructure",
        f"ssid={ssid}",
        "",
        "[wifi-security]",
        "auth-alg=open",
        "key-mgmt=wpa-psk",
        f"psk={secret}",
        "",
        "[ipv4]",
        "method=auto",
        "",
        "[ipv6]",
        "addr-gen-mode=default",
        "method=auto",
        "",
    ])
    out.write_text(profile)
    os.chown(out, os.getuid(), os.getgid())
    os.chmod(out, 0o600)
PY
  sudo chown -R "$USER:$USER" "$vault"
  chmod 700 "$vault" "$vault/iwd"
  chmod 600 "$vault"/*.nmconnection "$vault/iwd"/*.psk 2>/dev/null || true
  shopt -s nullglob
  for f in "$vault"/*.nmconnection; do
    base="$(basename "$f")"
    if [[ ! -e "$src/$base" ]]; then
      sudo install -m 600 -o root -g root "$f" "$src/$base"
    fi
  done
  shopt -u nullglob
  sudo mkdir -p "$iwd"
  sudo python3 - "$vault" "$iwd" <<'PY'
import pathlib, re, sys
vault, iwd = map(pathlib.Path, sys.argv[1:])

def iwd_filename(ssid):
    if re.fullmatch(r"[A-Za-z0-9 _-]+", ssid):
        return ssid + ".psk"
    return "=" + ssid.encode().hex() + ".psk"

def escape(value):
    value = value.replace("\\", "\\\\").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    if value.startswith(" "):
        value = "\\s" + value[1:]
    return value

written = 0
for src in vault.glob("*.nmconnection"):
    text = src.read_text(errors="replace")
    ssid = re.search(r"^ssid=(.*)$", text, re.M)
    secret = re.search(r"^psk=(.*)$", text, re.M)
    if not ssid or not secret or not secret.group(1):
        continue
    dest = iwd / iwd_filename(ssid.group(1))
    if dest.exists():
        continue
    if re.fullmatch(r"[0-9a-fA-F]{64}", secret.group(1)):
        body = "[Security]\nPreSharedKey=" + secret.group(1) + "\n"
    else:
        body = "[Security]\nPassphrase=" + escape(secret.group(1)) + "\n"
    dest.write_text(body)
    dest.chmod(0o600)
    written += 1
print(f"installed {written}")
PY
  if systemctl is-active NetworkManager >/dev/null 2>&1; then
    nmcli connection reload >/dev/null 2>&1 || true
  fi
  if systemctl is-enabled iwd >/dev/null 2>&1 || systemctl is-active iwd >/dev/null 2>&1; then
    sudo systemctl restart iwd >/dev/null 2>&1 || true
  fi
  say "Wi-Fi passwords are in ~/Dropbox/Vault/wifi."
}

install_cursor_agent() {
  if [[ -x "$HOME/.local/bin/agent" ]]; then
    say "Cursor agent CLI is already installed."
    return 0
  fi
  curl -fsSL https://cursor.com/install | bash
  if [[ ! -x "$HOME/.local/bin/agent" ]]; then
    say "Cursor agent CLI did not install."
    return 0
  fi
  say "Cursor agent CLI is installed. The command is agent."
}

set_qbittorrent_save_path() {
  mkdir -p "$HOME/Torrents" "$HOME/.config/qBittorrent"
  python3 - "$HOME/.config/qBittorrent/qBittorrent.conf" "$HOME/Torrents" <<'PY'
import pathlib, sys
conf, save = pathlib.Path(sys.argv[1]), sys.argv[2]
key = "Session\\DefaultSavePath"
text = conf.read_text() if conf.exists() else ""
lines = text.splitlines()
out = []
in_bt = False
found = False
for line in lines:
    if line.startswith("[") and line.endswith("]"):
        if in_bt and not found:
            out.append(f"{key}={save}")
            found = True
        in_bt = line == "[BitTorrent]"
    if in_bt and line.startswith(key + "="):
        out.append(f"{key}={save}")
        found = True
        continue
    out.append(line)
if in_bt and not found:
    out.append(f"{key}={save}")
    found = True
if not found:
    if out and out[-1] != "":
        out.append("")
    out += ["[BitTorrent]", f"{key}={save}"]
conf.write_text("\n".join(out).rstrip() + "\n")
PY
  say "qBittorrent saves to ~/Torrents."
}

set_obsidian_notes() {
  local notes="$HOME/Dropbox/Notes"
  say "Waiting for the Notes vault in Dropbox."
  until [[ -d "$notes" ]]; do
    sleep 2
  done
  mkdir -p "$HOME/.config/obsidian"
  python3 - "$HOME/.config/obsidian/obsidian.json" "$notes" <<'PY'
import json, os, sys, time
path, notes = sys.argv[1], sys.argv[2]
data = {"vaults": {}}
if os.path.exists(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except json.JSONDecodeError:
        data = {"vaults": {}}
if not isinstance(data, dict):
    data = {"vaults": {}}
vaults = data.setdefault("vaults", {})
if not isinstance(vaults, dict):
    vaults = {}
    data["vaults"] = vaults
target = os.path.realpath(notes)
found = False
for vault in vaults.values():
    if isinstance(vault, dict) and os.path.realpath(vault.get("path", "")) == target:
        vault["open"] = True
        found = True
if not found:
    vaults["dropbox-notes"] = {"path": notes, "ts": int(time.time() * 1000), "open": True}
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
  local autostart="$HOME/.config/hypr/autostart.lua"
  local encoded notes_url
  encoded=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$notes")
  notes_url="obsidian://open?path=${encoded}"
  mkdir -p "$HOME/.config/hypr"
  if [[ ! -f "$autostart" ]]; then
    printf '%s\n' "-- Extra autostart processes." >"$autostart"
  fi
  python3 - "$autostart" "$notes_url" <<'PY'
import pathlib, sys
path, url = pathlib.Path(sys.argv[1]), sys.argv[2]
text = path.read_text() if path.exists() else "-- Extra autostart processes.\n"
start = text.find("-- bootstrap-2 obsidian shelf")
if start != -1:
    text = text[:start].rstrip() + "\n"
text += f"""
-- bootstrap-2 obsidian shelf
o.window("^obsidian$", {{ workspace = "special:scratchpad silent" }})
o.window("md.obsidian.Obsidian", {{ workspace = "special:scratchpad silent" }})
o.launch_on_start("obsidian {url}")
"""
path.write_text(text)
PY
  hyprctl reload >/dev/null 2>&1 || true
  if pgrep -x obsidian >/dev/null 2>&1; then
    killall obsidian >/dev/null 2>&1 || true
    sleep 1
  fi
  if command -v obsidian >/dev/null 2>&1; then
    if command -v uwsm-app >/dev/null 2>&1; then
      uwsm-app -- obsidian "$notes_url" >/dev/null 2>&1 &
    else
      obsidian "$notes_url" >/dev/null 2>&1 &
    fi
  fi
  say "Obsidian opens ~/Dropbox/Notes on the shelf."
}

set_yaak_directory_sync() {
  local dir="$HOME/Dropbox/Vault/yaak"
  local db="$HOME/.local/share/app.yaak.desktop/db.sqlite"
  mkdir -p "$dir"
  if [[ -f "$db" ]] && python3 - "$db" "$dir" <<'PY'
import sqlite3, sys
db, directory = sys.argv[1:]
con = sqlite3.connect(db)
row = con.execute(
    "select count(*) from workspace_metas where setting_sync_dir = ?",
    (directory,),
).fetchone()
raise SystemExit(0 if row and row[0] else 1)
PY
  then
    say "Yaak syncs requests to ~/Dropbox/Vault/yaak."
    return 0
  fi
  if ! find "$dir" -maxdepth 1 -name 'yaak.wk_*.yaml' -print -quit | grep -q .; then
    if [[ -f "$db" ]]; then
      if pgrep -x yaak-app >/dev/null 2>&1 || pgrep -x yaak-app-client >/dev/null 2>&1; then
        killall yaak-app yaak-app-client yaaknode >/dev/null 2>&1 || true
        sleep 1
      fi
      python3 - "$db" "$dir" <<'PY'
import sqlite3, sys
db, directory = sys.argv[1:]
con = sqlite3.connect(db)
con.execute(
    """
    update workspace_metas
    set setting_sync_dir = ?, updated_at = CURRENT_TIMESTAMP
    where ifnull(setting_sync_dir, '') = ''
    """,
    (directory,),
)
con.commit()
PY
      if command -v uwsm-app >/dev/null 2>&1; then
        uwsm-app -- yaak-app >/dev/null 2>&1 &
      else
        yaak-app >/dev/null 2>&1 &
      fi
      say "Yaak writes requests to ~/Dropbox/Vault/yaak."
      say "Private environments stay out of that folder until you mark them sharable."
      return 0
    fi
    say "Waiting for Yaak requests in ~/Dropbox/Vault/yaak."
    until find "$dir" -maxdepth 1 -name 'yaak.wk_*.yaml' -print -quit | grep -q .; do
      sleep 2
    done
  fi
  if [[ ! -f "$db" ]]; then
    if command -v uwsm-app >/dev/null 2>&1; then
      uwsm-app -- yaak-app >/dev/null 2>&1 &
    else
      yaak-app >/dev/null 2>&1 &
    fi
    local _
    for _ in $(seq 1 40); do
      [[ -f "$db" ]] && break
      sleep 0.5
    done
    killall yaak-app yaak-app-client yaaknode >/dev/null 2>&1 || true
    sleep 1
  fi
  if [[ ! -f "$db" ]]; then
    say "Yaak did not create its database, so the requests were not imported."
    return 0
  fi
  if pgrep -x yaak-app >/dev/null 2>&1 || pgrep -x yaak-app-client >/dev/null 2>&1; then
    killall yaak-app yaak-app-client yaaknode >/dev/null 2>&1 || true
    sleep 1
  fi
  python3 - "$db" "$dir" <<'PY'
import json, os, sqlite3, sys
from datetime import date, datetime
from pathlib import Path
try:
    import yaml
except ImportError:
    raise SystemExit("python-yaml is not installed")

db_path, sync_dir = sys.argv[1], sys.argv[2]
tables = {
    "workspace": "workspaces",
    "http_request": "http_requests",
    "folder": "folders",
    "grpc_request": "grpc_requests",
    "websocket_request": "websocket_requests",
    "environment": "environments",
}

def snake(name):
    out = []
    for index, char in enumerate(name):
        if char.isupper() and index:
            out.append("_")
        out.append(char.lower())
    return "".join(out)

def json_default(value):
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    raise TypeError(f"cannot encode {type(value).__name__}")

def cell(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, separators=(",", ":"), default=json_default)
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, bool):
        return int(value)
    return value

con = sqlite3.connect(db_path)
columns = {}
for table in set(tables.values()) | {"workspace_metas"}:
    columns[table] = [row[1] for row in con.execute(f"pragma table_info({table})")]
imported = {"http_requests": 0}
workspace_id = None
documents = []
for path in Path(sync_dir).glob("yaak.*.yaml"):
    document = yaml.safe_load(path.read_text())
    if isinstance(document, dict):
        documents.append(document)
documents.sort(key=lambda document: {
    "workspace": 0,
    "folder": 1,
    "environment": 2,
    "http_request": 3,
    "grpc_request": 3,
    "websocket_request": 3,
}.get(document.get("model"), 9))
for document in documents:
    table = tables.get(document.get("model"))
    if table is None:
        continue
    data = {}
    for key, value in document.items():
        column = snake(key)
        if column in columns[table]:
            data[column] = cell(value)
    if "id" not in data:
        continue
    if table == "workspaces":
        workspace_id = data["id"]
    names = list(data)
    placeholders = ",".join("?" for _ in names)
    updates = ",".join(f"{name}=excluded.{name}" for name in names if name != "id")
    con.execute(
        f"insert into {table} ({','.join(names)}) values ({placeholders}) on conflict(id) do update set {updates}",
        [data[name] for name in names],
    )
    imported[table] = imported.get(table, 0) + 1
if workspace_id is None:
    raise SystemExit("Yaak workspace file was not imported")
meta_cols = columns["workspace_metas"]
existing = con.execute(
    "select id from workspace_metas where workspace_id = ?",
    (workspace_id,),
).fetchone()
if existing:
    con.execute(
        "update workspace_metas set setting_sync_dir = ?, updated_at = CURRENT_TIMESTAMP where workspace_id = ?",
        (sync_dir, workspace_id),
    )
else:
    con.execute(
        """
        insert into workspace_metas (id, model, workspace_id, setting_sync_dir)
        values (?, 'workspace_meta', ?, ?)
        """,
        (f"wm_{workspace_id[3:]}", workspace_id, sync_dir),
    )
for (other_id,) in con.execute("select id from workspaces where id != ?", (workspace_id,)):
    requests = con.execute(
        "select count(*) from http_requests where workspace_id = ?",
        (other_id,),
    ).fetchone()[0]
    if requests:
        continue
    for table in ("http_requests", "folders", "environments", "grpc_requests", "websocket_requests", "workspace_metas"):
        if "workspace_id" in columns.get(table, []):
            con.execute(f"delete from {table} where workspace_id = ?", (other_id,))
    con.execute("delete from workspaces where id = ?", (other_id,))
con.commit()
print(f"imported {imported.get('http_requests', 0)} Yaak requests")
PY
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- yaak-app >/dev/null 2>&1 &
  else
    yaak-app >/dev/null 2>&1 &
  fi
  say "Yaak requests are imported from ~/Dropbox/Vault/yaak."
  say "Private environments stay out of that folder until you mark them sharable."
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
install_repo_pkgs python-secretstorage python-yaml
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

say "7. Work apps"
install_work_apps
set_qbittorrent_save_path
set_obsidian_notes
set_yaak_directory_sync
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user restart vault-sync.service || true
fi
"$HOME/.local/bin/vault-sync" reconcile || say "TablePlus sync did not finish."
apply_local_domains
sync_wifi_credentials

say ""
say "Still to do by hand:"
say "1. In the Bitwarden app: Settings, Unlock with system authentication. The script records the setting. The unlock key is created only when that box is checked."
say "2. In the Chromium Bitwarden extension: sign in once, to the same EU account."
say "3. Extension Settings, Account security: Share unlock with Desktop. If that line is missing, Unlock with biometrics."
say "4. In the extension, Timeout Never and Timeout action Lock, if those controls are still shown and not managed by the desktop app."
say "5. In a terminal: gh auth login"
say "6. In a terminal: aws configure"
