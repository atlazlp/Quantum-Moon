# Quantum Moon — installation tutorial

This guide targets **Arch Linux / CachyOS** with **Hyprland**. You will install **Caelestia**, copy Quantum Moon’s Hypr and shell files into `$HOME/.config`, register the wallpaper tooling path, optionally regenerate slot wallpapers from **`starbg.png`**, apply **Quickshell patches**, and run **`qm-apply`** once.

I use **Brazilian Portuguese** defaults day to day — `**kb_layout = br`** (ABNT2) in `**caelestia/hypr-user-local.conf**` and São Paulo timezone on the host machine. If you are elsewhere, plan to switch **keyboard layout**, `**timedatectl` timezone**, and `**locale`** to match your region (see **[docs/post-install-reference.md](post-install-reference.md)**).

**Upstream versions used as a reference when writing this doc** (use whatever your distro ships and re-run patches after major upgrades):

- `caelestia-shell`, `caelestia-cli`, Caelestia dots under `$HOME/.local/share/caelestia`

---

## 1. Prerequisites

Install or have available:


| Requirement                                               | Notes                                         |
| --------------------------------------------------------- | --------------------------------------------- |
| `base-devel`, `git`, `git-lfs`, `hyprland`, `jq`          | `git-lfs` required for `center.mp4` wallpapers (§2) |
| `yay` or another AUR helper                               | Required by `./install-caelestia.sh`          |
| ImageMagick (`magick` / `convert`)                        | Only if you re-run `qm-init-mvp-assets` (§6)  |
| Network                                                   | For cloning upstream Caelestia and AUR builds |


The installer script also tries to install **polkit-gnome**, **foot**, **kitty**, **hyprpaper**, **mpvpaper**, **nautilus**, **qt6ct**, and **frameworkintegration** (`|| true` so missing packages do not abort the whole line). **hyprpaper** is started on login and driven by `**qm-apply`**; **mpvpaper** is optional center-monitor video when `**center.mp4`** exists.

---

## 2. Clone Quantum Moon

Center-monitor videos (`center.mp4` per mode) are stored with **Git LFS** so the repository can live on GitHub. After clone they still sit at the same paths, for example `quantum-moon/modes/timber-hearth/wallpapers/center.mp4` — nothing in `qm-apply` or mpvpaper changes.

Install **git-lfs** once, enable it for your user, then clone:

```bash
sudo pacman -S git-lfs
git lfs install

mkdir -p "$HOME/src"
git clone https://github.com/atlazlp/Quantum-Moon.git "$HOME/src/Quantum-Moon"
cd "$HOME/src/Quantum-Moon"
git lfs pull
```

If videos are missing (tiny pointer files instead of full `.mp4`), run `git lfs pull` again with `git-lfs` installed.

**Maintainers** pushing large videos for the first time: after `git-lfs` is installed, run `./scripts/git-lfs-migrate-center-videos.sh` from the repo root, then push (see script output if history was rewritten).

All paths below assume `cd` into that directory.

---

## 3. First-time Caelestia install

```bash
./install-caelestia.sh
```

What it does:

1. Clones **caelestia-dots** to `**$HOME/.local/share/caelestia`** (if missing).
2. Builds `**caelestia-meta**` from that tree with `yay`.
3. Replaces `**$HOME/.config/hypr**` with a **symlink** to the upstream `hypr` directory (existing directory is moved to `hypr.bak.<timestamp>`).
4. Copies `**caelestia/`** snippets into `**$HOME/.config/caelestia/**`, `**hyprpaper.conf**` into `**$HOME/.config/hypr/**`, WirePlumber drop-in, helper scripts, and `**caelestia/assets/**` (logo, GIFs, static wallpapers used by hyprpaper).
5. Installs `**xdg-user-dirs**`, runs `**xdg-user-dirs-update**`, and merges **Nautilus / GTK sidebar bookmarks** (Home, Documents, Downloads, etc.) via `**scripts/install-nautilus-sidebar-bookmarks.sh`** (adds any missing entries; run `**nautilus -q**` afterward if Files was open).

Log out and back in if the shell or compositor does not start.

---

## 4. Bundled media (already in the repo)

After install, these live under `**$HOME/.config/caelestia/assets/**`:


| Role                                            | File                                                       |
| ----------------------------------------------- | ---------------------------------------------------------- |
| Shell logo                                      | `logo.png`                                                 |
| Session strip GIF                               | `session-power-tab.gif`                                    |
| Background GIF                                  | `mediaGif.gif`                                             |
| Static hyprpaper crops (triple-monitor example) | `wallpapers/bg-hdmi-a-1.png`, `bg-dp-2.png`, `bg-dp-3.png` |


`**caelestia/shell.json**` and `**caelestia/hyprpaper.conf**` point at those paths. Rename files in `**caelestia/monitors/**` and edit `**caelestia/hypr-user.conf**` `monitor=` lines if your outputs differ from the examples (`HDMI-A-1`, `DP-2`, `DP-3`).

---

## 5. Quantum Moon CLI paths

```bash
./scripts/install-quantum-moon.sh
```

Creates `**$HOME/.config/caelestia/quantum-moon-root**` (single line: absolute path to Quantum Moon’s `**quantum-moon/**` directory) and symlinks `**qm-apply**`, `**qm-random**`, and `**qm-init-mvp-assets**` into `**$HOME/.local/bin**`.

### PATH and Hypr — important

Do **not** set `env = PATH, $HOME/.local/bin:$PATH` in Hypr: during early config parse, `**$PATH`** can be incomplete and collapse to only `**$HOME/.local/bin**`, breaking `**/usr/bin/sh**` and taking down Caelestia after a reload.

Prefer:

- **Fish:** `fish_add_path -m $HOME/.local/bin`
- Other shells: set PATH in `**~/.profile`** / pam-environment as appropriate.

Quantum Moon binds use `**quantum-moon-root**` and bash, so `**qm-random**` does not need to be on PATH for **Super+Shift+M**.

Optional cleanup if you previously wrote a broken systemd environment drop-in:

```bash
rm -f ~/.config/environment.d/10-local-bin.conf
```

For systemd user units that need `**$HOME/.local/bin**`, use an explicit line with **absolute** paths (systemd does not expand `**$HOME`** in all contexts), for example:

`PATH=/home/yourname/.local/bin:/usr/local/bin:/usr/bin`

---

## 6. Mode wallpapers (`starbg` cuts)

The repository already ships per-mode assets under `quantum-moon/modes/<mode>/`: `wallpapers/slot-0.png` … `slot-2.png`, planet logos (`logo.png` / `logo-lq.png`), palettes, and optional `center.mp4`. You can run `qm-apply` without generating anything first.

**`qm-init-mvp-assets`** is optional. It **only** rebuilds the three slot PNGs per mode by cropping from a starfield source:

- `quantum-moon/modes/<mode>/starbg.png` if present, otherwise
- shared `quantum-moon/modes/starbg.png`

It uses **ImageMagick** (`magick` or `convert`), scales the source slightly, then crops three **1920×1080** views. It does **not** create or overwrite planet logos.

```bash
qm-init-mvp-assets
```

Use this when you replace `starbg.png` or want fresh slot crops. **`install-quantum-moon.sh` does not run this command.**

---

## 7. Optional center-monitor video (mpvpaper)

Install **[mpvpaper](https://github.com/GhostNaN/mpvpaper)** (often from the AUR). Each mode can use `quantum-moon/modes/<mode>/wallpapers/center.mp4` beside the slot PNGs. In this repository those files are on **Git LFS** — use §2 (`git-lfs`, `git lfs pull`) so the real videos are present locally.

`qm-apply` starts or restarts mpvpaper for that clip; `qm-video-watch` (started from `hypr-user.conf` after `qm-apply --persisted`) pauses playback when the center output’s focused workspace has windows.

If `center.mp4` is missing or mpvpaper is not installed, behavior falls back to hyprpaper only.

Re-run `**./scripts/install-quantum-moon.sh**` if you want `**qm-video-watch**` / `**qm-video-restart**` symlinked into `**$HOME/.local/bin**` for debugging.

---

## 8. Quickshell patches

```bash
./scripts/apply-caelestia-sidebar-screen-patch.sh
```

Restart Caelestia (**Ctrl+Super+Alt+R**).

### If you see `type Drawers unavailable`

Quickshell often rejects ES-next syntax in `**.qml`**. Re-apply patches from an updated clone:

```bash
git pull
./scripts/apply-caelestia-sidebar-screen-patch.sh
caelestia shell -d
```

If it still fails, reset the packaged shell tree then patch again:

```bash
mv ~/.config/quickshell/caelestia ~/.config/quickshell/caelestia.bak.$(date +%s)
cp -a /etc/xdg/quickshell/caelestia ~/.config/quickshell/caelestia
./scripts/apply-caelestia-sidebar-screen-patch.sh
caelestia shell -d
```

### `merge-bar-quantum-moon.sh`

This helper **removes** a legacy `**quantumMoon`** entry from `**bar.entries**` in `**$HOME/.config/caelestia/shell.json**` if present. The Quantum Moon UI in this setup is the **top-edge hover panel**, not a bar chip. Run it after `**jq`** is installed if you are migrating from an older config:

```bash
./quantum-moon/scripts/merge-bar-quantum-moon.sh
```

---

## 9. Apply a mode

With Hyprland running:

```bash
qm-apply eye-of-the-universe
```

This sets hyprpaper per output (up to three), updates `**$HOME/.config/hypr/hyprpaper.conf**` for next boot, sets `**general.logo**` in `**shell.json**`, writes the planet palette to `**$HOME/.local/state/caelestia/scheme.json**`, records state under `**$HOME/.local/state/quantum-moon/**`, and optionally manages mpvpaper.

On login, `**qm-apply --persisted**` restores the last mode (see `**caelestia/hypr-user.conf**`).

---

## 10. Monitors and wallpaper slots

Outputs names come from:

```bash
hyprctl monitors
```

Use those names in `**caelestia/hypr-user.conf**` and in `**caelestia/monitors/<NAME>/shell.json**`.

`**qm-apply**` sorts monitors by `**x**`, then `**y**`, and maps:


| File                    | Monitor                                                                                       |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| `slot-0.png`            | Leftmost                                                                                      |
| `slot-1.png`            | Middle (if any)                                                                               |
| `slot-2.png`            | Rightmost                                                                                     |
| `center.mp4` (optional) | Same output as `**slot-1**` when two or more outputs exist; single-head uses the only monitor |


### One or two monitors

`**qm-apply**` only assigns `**slot-0**` / `**slot-1**` / `**slot-2**` for monitors that actually exist (up to three). You do **not** need three panels for the scripts to work.

`**caelestia/hypr-user.conf`** still ships three example `**monitor=**` lines for the maintainer’s triple-head desk; Hyprland generally ignores outputs that are unplugged. Remove or edit lines you do not need if your machine behaves oddly.

**Caelestia bar:** `**shell.json`** uses `**bar.excludedScreens**` so the bar appears only on the **center** monitor in that triple layout. If **your only connected monitor’s Hypr name is listed there**, the bar will stay hidden everywhere — set `**excludedScreens`** to `**[]**` (or drop your connector’s name), restart the shell, then tune again if you add monitors later.

The bundled `**caelestia/hyprpaper.conf**` lists three outputs as a fallback before the first `**qm-apply**`; after `**qm-apply**`, the file is regenerated for connected outputs only.

More detail: **[docs/post-install-reference.md](post-install-reference.md)**.

---

## 11. Baseline backup (optional)

```bash
./scripts/backup-quantum-moon-baseline.sh
```

Writes `**backup/quantum-moon-baseline-<timestamp>.zip**` or `**.tar.gz**` with the repo, relevant `**$HOME/.config**` copies, and upstream revision metadata.

---

## 12. Updating Caelestia

```bash
cd ~/.local/share/caelestia
git pull
yay -Bi . --noconfirm --needed
cd "$HOME/src/Quantum-Moon"
./scripts/apply-caelestia-sidebar-screen-patch.sh
```

Restart the shell. Re-diff `**modules/bar/Bar.qml**` against upstream if the bar layout changed.

---

## 13. Default applications and shortcuts

Application choices are in `**caelestia/hypr-vars.conf**` (`**$terminal**`, `**$browser**`, `**$editor**`, `**$fileExplorer**`). Most shortcuts come from upstream Caelestia `**hypr**` snippets plus Quantum Moon’s `**hypr-user.conf**` overrides.

Full tables (locale/timezone notes, monitor/bar caveats, bind list): **[docs/post-install-reference.md](post-install-reference.md)**. Upstream source of truth: `**$HOME/.local/share/caelestia/hypr`** after install.

---

## 14. Legal / license / sharing

All **intellectual property** in *Outer Wilds*—story, characters, names, artwork, audio, branding, and trademarks—belongs to **Mobius Digital**, **Annapurna Interactive**, and their respective licensors. **Quantum Moon** is a free, fan-made homage by **[atlazlp](https://github.com/atlazlp)** ([repository](https://github.com/atlazlp/Quantum-Moon)), built while learning **Arch Linux** and **Hyprland**. It is **not** sponsored, endorsed, or affiliated with those rights holders, and this project implies no connection to the official game or its publishers. Game recordings in this project were captured from a legally purchased copy.

**Original code and configuration** in this repository (for example shell scripts, Hyprland config snippets, and prose you author yourself) is released under the **[MIT License](../LICENSE)** unless a specific file states otherwise. That license covers only those materials; it does **not** grant rights to game assets, bundled third-party media, or anyone else’s trademarks or copyrights. Respect those owners when you copy, fork, or redistribute this work.

This desktop stacks on **[Caelestia](https://github.com/caelestia-dots/caelestia)** (Quickshell-based shell) and **[Hyprland](https://github.com/hyprwm/Hyprland)** (Wayland compositor). Credit them when you share derivative setups, and follow **their** licenses for their upstream code.