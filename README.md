# Omarchy bootstrap

Personal setup for a fresh [Omarchy](https://omarchy.org/) 4.0.4 install. `bootstrap-2.sh` is safe to run again. It skips work that is already done.

```bash
curl -fsSL https://raw.githubusercontent.com/LukasCaha/omarchy/main/bootstrap-2.sh | sh
```

From a checkout of this repo, `./bootstrap-2.sh` uses the `vault-sync` file next to it. The `curl` form downloads `vault-sync` from this same repository.

The script asks for your password when it writes the Chromium extension policy and the Bitwarden unlock rule. Dropbox and Bitwarden each need one sign-in in their own window. The script waits for those and then continues.

`bootstrap.sh` is the older checklist. Use `bootstrap-2.sh`.

## What it does

### Keyboard

Czech QWERTZ is applied before any later password prompt, and saved in `~/.config/hypr/input.lua`. Scroll follows the wheel, for the mouse and the touchpad: down moves the page down. Hyprland is reloaded so that takes effect in the current session.

### Dropbox

Installs the Omarchy Dropbox service if it is missing, starts it, and waits until you sign in from the tray icon. The Dropbox website does not link this computer.

`~/Dropbox/Archive` is excluded from local sync. The cloud copy stays. This computer does not keep those files. If the folder is already on disk, Dropbox removes the local copy when the exclude is added.

The script then waits until `~/Dropbox/Vault/browser/chromium/Bookmarks` has synced.

### Bitwarden desktop

Installs the desktop app and the `bw` CLI if they are missing. The server is set to the EU vault, `https://vault.bitwarden.eu`, before the first sign-in.

After you sign in, the script quits Bitwarden and writes its settings, then starts it again. A running Bitwarden would overwrite that file on exit. The settings are:

- SSH agent on, at `~/.bitwarden-ssh-agent.sock`
- No prompt before each SSH use
- Vault timeout Never, timeout action Lock
- Start in the tray and keep running in the background
- Unlock with system authentication recorded in the app settings

An active PC session is allowed to use the Bitwarden unlock through polkit. A locked session is not. The unlock key itself is created only when you check **Unlock with system authentication** in the app. The script cannot check that box.

### Chromium

Installs Chromium if it is missing. A force-install policy adds uBlock Origin Lite and the Bitwarden extension, and points the extension at the EU vault.

On an empty profile it copies bookmarks from `~/Dropbox/Vault/browser/chromium/Bookmarks`. A profile that already has bookmarks is left alone. It then downloads bookmark icons into Chromium's favicon database so they show before you visit those sites.

The profile is set to vertical tabs, with the tab memory button and tab-group button off. uBlock Origin Lite and Bitwarden are pinned. The toolbar also pins developer tools, downloads, and the QR code button.

### Vault sync

Installs `vault-sync` to `~/.local/bin/vault-sync` and a user service that watches Chromium.

When Chromium quits, these files copy to `~/Dropbox/Vault`:

- `~/.config/chromium/Default/History`
- `~/.config/chromium/Default/Shortcuts`

When an interactive bash exits, these files copy too, and the next shell pulls them on startup:

- `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.bash_history`
- `~/.config/starship.toml`
- `~/.local/share/zoxide/db.zo`
- `~/.ssh/config`, `~/.ssh/known_hosts`
- `~/.ssh/id_ed25519.pub`, `~/.ssh/id_ed25519_vps.pub`

If one side is empty and the other has real content, the full copy wins, so a new machine does not wipe the Vault. Otherwise the newer file wins. History and Shortcuts are copied with SQLite's backup API, and only while Chromium is closed.

The synced `~/.bashrc` is what points `SSH_AUTH_SOCK` at the Bitwarden agent socket when that socket exists.

### SSH

Public SSH files move between `~/.ssh` and `~/Dropbox/Vault/ssh` when one side is missing. Private keys stay in Bitwarden. They have to be items of type SSH key. A secure note, or a fingerprint written in a note, is not something the agent can use.

### Desktop

- Theme: Catppuccin Latte
- Monospace font: Geist Mono (`otf-geist-mono-nerd` if it is not installed yet)
- Top bar: transparent. The clock and CPU temperature refresh every second. Clicking the temperature opens btop. The battery icon stays an icon, and the percent sits to its right, at the same size.
- Status icons left of the clock stay visible
- Tray icons on the right stay visible. There is no hover chevron.
- Wallpaper: the second Catppuccin Latte image, not the first
- Screenshots go to `~/Dropbox/Screenshots`
- Screen recordings go to `~/Dropbox/ScreenRecordings`

The screenshot and recording paths are read at login. They apply after the next login.

Nautilus gets these sidebar bookmarks, each with an icon: Desktop, Projects, Downloads, Dropbox Resources, Screenshots, ScreenRecordings, and Dropbox. Omarchy does not create `~/Desktop` on its own, because it sets the desktop directory to your home folder. The script creates `~/Desktop` and points the desktop directory there.

## What you still do by hand

The script prints this list when it finishes:

1. In the Bitwarden app, turn on **Unlock with system authentication**.
2. In the Chromium Bitwarden extension, sign in once to the same EU account.
3. In the extension, under **Account security**, turn on **Share unlock with Desktop**. If that line is missing, use **Unlock with biometrics**.
4. In the extension, set timeout to Never and timeout action to Lock, if those controls are still shown.
5. If no tray icons were open yet, right-click the `<` on the bar and pin each one.

Put the SSH private keys into Bitwarden as SSH keys before expecting `ssh` to work. Sign in to Dropbox from the tray, and to the Bitwarden desktop app, the first time.

## What it does not do

- It does not install Omarchy. It starts from an installed Omarchy 4.0.4 system.
- It does not sign in to Dropbox, Bitwarden, or the Chromium Bitwarden extension for you.
- It does not check the Bitwarden **Unlock with system authentication** box, and it does not turn on **Share unlock with Desktop** in the extension.
- It does not copy private SSH keys, passwords, or the Bitwarden vault. Those stay in Bitwarden.
- It does not sync `~/.config/mise`. Tool versions stay per machine.
- It does not sync Chromium extensions' own data, cookies, or an open browser's History database.
- It does not move existing screenshots and recordings into Dropbox. It only changes where new ones are saved, after the next login.
- It does not exclude any Dropbox folder except `Archive`.
- It does not theme Waybar. Omarchy 4 uses its own bar.
- It does not change window rules, keybindings, monitors, or the wallpaper beyond the Catppuccin Latte theme.
- It does not publish anything in `~/Dropbox/Vault` to this git repository.

## What stays out of this repository

This repository is public because the bootstrap is fetched with `curl`. It holds the script and `vault-sync` only.

Bookmarks, browser history, shell history, SSH config, and public keys live in `~/Dropbox/Vault` on your account. Private keys live in Bitwarden. Do not commit `.env` files, keyrings, Chromium profiles, or private keys.
