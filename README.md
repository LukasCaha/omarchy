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

Czech QWERTZ is applied before any later password prompt, and saved in `~/.config/hypr/input.lua`. The mouse follows the wheel: down moves the page down. Touchpad scroll is reversed, so the content follows the fingers. Hyprland is reloaded so that takes effect in the current session. A re-run updates a touchpad that was previously set to follow the wheel.

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

The same service also copies TablePlus connection settings and keyring passwords to `~/Dropbox/Vault/tableplus` about every 30 seconds. A fresh machine receives them on the next `vault-sync` run.

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

### Work apps

Installs these if they are missing. `omarchy-pkg-add` only uses pacman, so AUR packages go through `omarchy-pkg-aur-add`.

From the repositories: AWS CLI, VLC, GIMP, qBittorrent, Obsidian, Yaak, and `python-secretstorage`. From the AUR: AWS SAM CLI (`aws-sam-cli-bin`), Grok bot (`grok-bot-bin`), and Fastpotify (`fastpotify-bin`). If Yaak is not in the repositories, the script installs `yaak-bin` instead.

TablePlus is the AUR package `tableplus`. TablePlus only publishes a `.deb`, and that AUR package builds it with `makepkg`. The libraries come from Arch. The PKGBUILD pins a `.deb` TablePlus has already removed, so the download returns 404. The script keeps the AUR package and points that build at the `.deb` that is still published.

The Cursor agent CLI is installed with the official installer when `agent` is not already on `PATH`. That puts `agent` in `~/.local/bin`.

qBittorrent's default save path is `~/Torrents`. The script creates that folder.

Obsidian opens the Notes vault at `~/Dropbox/Notes`. The notes themselves come from Dropbox. The script waits until that folder has synced, registers it as the open vault, and starts Obsidian on the shelf at login. Super+S still toggles the shelf.

TablePlus connections, keyring passwords, and the license sync through `~/Dropbox/Vault/tableplus` while `vault-sync` is running. The license is `~/.tableplus/.tblicensenix`, together with `~/.tableplus/.tbid`. Those files stay in the Vault. They are not part of this repository. On the new machine, `vault-sync` copies them back before TablePlus is opened.

Yaak directory sync uses `~/Dropbox/Vault/yaak`. On a machine that already has requests and an empty sync folder, the script sets that path and Yaak writes one YAML file per request. On a new machine the script waits for those files, imports them into Yaak, and keeps the workspace pointed at that folder. Environments stay out of the folder until you mark them sharable.

## What you still do by hand

The script prints this list when it finishes:

1. In the Bitwarden app, turn on **Unlock with system authentication**.
2. In the Chromium Bitwarden extension, sign in once to the same EU account.
3. In the extension, under **Account security**, turn on **Share unlock with Desktop**. If that line is missing, use **Unlock with biometrics**.
4. In the extension, set timeout to Never and timeout action to Lock, if those controls are still shown.
5. If no tray icons were open yet, right-click the `<` on the bar and pin each one.
6. In a terminal, `agent` is `~/.local/bin/agent`. Sign in once if the CLI asks.
7. In a terminal: `gh auth login`.
8. In a terminal: `aws configure`.

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
- It does not change keybindings or monitors. The only extra window rule puts Obsidian on the shelf. The wallpaper change is the second Catppuccin Latte image.
- It does not publish anything in `~/Dropbox/Vault` to this git repository.

## Todo

Not in the script yet. Packages can be installed by the script. Repos, `.env` files, and app databases with passwords stay off this public repository and have to be copied by hand.

- **Projects.** `~/Projects` is the big one. The Youklid repos live only on this disk. The new machine needs those clones, including anything not pushed.
- **Laravel `.env` files.** They sit inside the project directories (about 17 of them), and `~/Spaces` only symlinks those directories. Copying the repos without the `.env` files leaves the apps unable to boot. Do not commit them here.
- **Spaces.** Clone `~/Spaces`, build `bin/w`, link it to `~/.local/bin/w`, and keep `workspaces.yaml`. The hubs point at `~/Projects`, so this waits on the repos being there.
- **Herdr.** Install the `herdr` binary to `~/.local/bin/herdr` and copy `~/.config/herdr`. `config.toml` is only the Catppuccin Latte theme. `session.json` is the seven workspaces under `~/Projects`, so this waits on those repos.
- **Local domains.** `~/.config/domains/sites` and the `domains` command sync through `~/Dropbox/Vault/domains`. The script writes those names into `/etc/hosts` and points `*.test` at `127.0.0.1` with dnsmasq. Port 8000 is just where the app listens.
- **Wi-Fi.** Saved networks, including passwords, copy to `~/Dropbox/Vault/wifi`. The new machine installs them for iwd, which is the Wi-Fi menu. NetworkManager is disabled, so its profiles alone do not show up there. Do not commit that folder.
- **Cursor skills `/dr` and `/save`.** Done. `vault-sync` copies `~/.cursor/skills/dr` and `~/.cursor/skills/save` to `~/Dropbox/Vault/cursor/skills`. Do not commit that folder.
- **GitHub login.** Name and email are already written by the Omarchy installer. Push and pull on this machine go through `gh`, and that token sits in the login keyring, so it does not come across. On the new machine, install `github-cli` and run `gh auth login` once. That sets the credential helper too.
- **AWS credentials.** The AWS CLI and SAM CLI are installed. `~/.aws` is not copied. Test the default profile with `aws sts get-caller-identity`. If the login has expired, run `aws login`. The separate `cursor` profile is `aws sts get-caller-identity --profile cursor`.
- **TablePlus.** Done. `vault-sync` copies connection settings and keyring passwords to `~/Dropbox/Vault/tableplus` about every 30 seconds. Do not commit that folder.
- **Yaak.** Done. Requests sync through `~/Dropbox/Vault/yaak`. Environments are not used.

## What stays out of this repository

This repository is public because the bootstrap is fetched with `curl`. It holds the script and `vault-sync` only.

Bookmarks, browser history, shell history, SSH config, and public keys live in `~/Dropbox/Vault` on your account. Private keys live in Bitwarden. Do not commit `.env` files, keyrings, Chromium profiles, or private keys.
