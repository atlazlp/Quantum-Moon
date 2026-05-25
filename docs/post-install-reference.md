# Post-install reference

Hyprland keybindings mostly come from upstream **Caelestia** under `$HOME/.local/share/caelestia/hypr`. Quantum Moon layers **`caelestia/hypr-user.conf`** and **`caelestia/hypr-user-local.conf`** on top. Use this page after you finish **[installation-tutorial.md](installation-tutorial.md)**.

---

## Maintainer defaults (Brazil)

Quantum Moon is maintained from **Brazil**. Fresh installs ship:

- **`kb_layout = br`** (ABNT2) and Brazilian Portuguese-friendly typing behavior in **`caelestia/hypr-user-local.conf`** — edit if you use another layout.

If that does not match your hardware or region:

| Goal | What to change |
|------|----------------|
| Keyboard layout / variant | **`~/.config/caelestia/hypr-user-local.conf`** → `input { kb_layout = … }` (and optional `kb_variant`). Reload: **`hyprctl reload`**. |
| System timezone | **`timedatectl list-timezones`** then **`sudo timedatectl set-timezone Region/City`** (example maintainer zone: **`America/Sao_Paulo`**). |
| Locale (locale-gen, LANG) | **`/etc/locale.conf`** and **`locale-gen`** on Arch — follow the Arch wiki “Locale” article. |

---

## Fewer than three monitors

**Quantum Moon (`qm-apply`)** already supports **one, two, or three** connected outputs: it sorts monitors left→right and assigns **`slot-0`**, **`slot-1`**, **`slot-2`** only for monitors that exist (up to three).

**`caelestia/hypr-user.conf`** still lists **three** example **`monitor=`** lines (`HDMI-A-1`, **`DP-2`**, **`DP-3`**) for the maintainer’s desk. Hyprland normally ignores rules for outputs that are **not plugged in**. If anything behaves oddly on your machine, delete or comment out the **`monitor=`** lines you do not need and keep only **`hyprctl monitors`** names you use.

**`caelestia/hyprpaper.conf`** in the repo lists three outputs as a **static fallback** before the first **`qm-apply`**. Extra **`wallpaper { monitor = … }`** entries for missing connectors are usually harmless; after **`qm-apply`**, the file is rewritten for **currently connected** monitors only.

**Important — Caelestia bar visibility:** **`shell.json`** sets **`bar.excludedScreens`** so the bar appears only on the **center** panel in the triple-head layout. If **your only connected monitor’s name appears in that list**, the bar will stay hidden on every screen. Fix:

```bash
# Edit ~/.config/caelestia/shell.json — set for example:
# "excludedScreens": []
```

Then restart the shell (**Ctrl+Super+Alt+R**). I maintain my committed values as-is so my layout keeps working.

---

## Overrides introduced by Quantum Moon (`hypr-user.conf`)

These differ from stock Caelestia; everything else matches upstream binds unless you changed them locally.

| Binding | Action |
|---------|--------|
| **Super+D** | Window overview / picker (`workspace-overview-toggle.sh`) |
| **Alt+Tab** / **Shift+Alt+Tab** | Cycle windows in picker order (`window-alt-tab-cycle.sh`) |
| **Super+Shift+A** | Activity monitor script |
| **Super+Shift+H** | Toggle onboard analog line-out vs front headphone port (`audio-toggle-analog-output.sh`) — see below |
| **Super+Shift+M** | Random Quantum Moon mode (`qm-random`) |
| **Ctrl+Super+Alt+R** | Restart Quickshell + Caelestia shell + hyprpaper reload + optional mpvpaper sync |

**Super alone (release):** toggles the launcher even over a fullscreen app. The shell uses the overlay layer, grabs pointer focus for the whole screen, and dismisses when you click outside (same as the window picker). Requires **`general.showOverFullscreen": true`** in **`shell.json`** (shipped in this repo) and a Quickshell rebuild after pulling shell patches.

---

## Qt (qt6ct)

**`caelestia/hypr-env-qt.conf`** sets **`QT_QPA_PLATFORMTHEME=qt6ct`** for the Hyprland session. **`qm-apply`** updates **`~/.config/qt6ct/`** to match the active palette.

---

## Analog audio (ALC897-class onboard)

**`config/wireplumber/wireplumber.conf.d/51-alsa-analog-ports.conf`** and the patched **Audio** popout / **`scripts/audio-toggle-analog-output.sh`** target a specific onboard codec layout (**PCI id `11_00.6`** style paths). On other PCs the toggle bind **no-ops** safely (script exits without changing ports).

To target another card/sink, set environment variables when debugging:

- **`AUDIO_ANALOG_CARD`**
- **`AUDIO_ANALOG_SINK`**

---

## Workspace and session (upstream Caelestia pattern)

Illustrative defaults (confirm in **`$HOME/.local/share/caelestia/hypr`** on your install):

| Binding | Typical action |
|---------|------------------|
| **Super+1…0** | Workspace 1–10 on current monitor |
| **Ctrl+Super+1…0** | Jump workspace “decades” |
| **Super+Alt+1…0** | Move window to workspace 1–10 |
| **Super+S** | Toggle special workspace view (`caelestia toggle specialws`) |
| **Super+Alt+S** / **Ctrl+Super+S** / **Ctrl+Super+Space** | Move focused window into/out of `special:special` (`toggle-special-window.sh`) |
| **Super+arrows** | Focus direction |
| **Super+Shift+arrows** | Move window |
| **Super+Q** | Close |
| **Super+F** | Fullscreen |

Launcher, sidebar, drawers, screenshots, and media keys follow upstream **`keybinds.conf`** / **`variables.conf`**.

---

## Application variables

Set in **`caelestia/hypr-vars.conf`** (installed to **`~/.config/caelestia/`**):

| Variable | Commit default |
|----------|----------------|
| **`$terminal`** | **kitty** |
| **`$browser`** | **firefox** |
| **`$editor`** | **`cursor-clean.sh`** wrapper |
| **`$fileExplorer`** | **nautilus** (via **`nautilus-wrap.sh`**) |
| **`$cursorTheme`** | **capitaine-cursors** |

---

## Nautilus (Files): sidebar, volumes, and mounts

**GTK bookmarks (your folders):** Run **`scripts/install-nautilus-sidebar-bookmarks.sh`** after cloning or pulling Quantum Moon (closing Files is **not** enough — it does not rewrite **`gtk-3.0/bookmarks`** or **`gtk.css`**). Then **`nautilus -q`** so GTK reloads CSS.

The script writes **`~/.config/gtk-3.0/bookmarks`** and **`~/.config/gtk-4.0/bookmarks`** in **fixed order**: **Documents … Templates** first, then **`nautilus-sidebar-extra`** mounts (so drives stay **last** among template bookmarks). Extra bookmark lines you added manually are **kept after** that block if their URI was not already listed (**`NAUTILUS_BOOKMARKS_FORCE=1`** drops those extras).

**Builtin rows (Recent / Starred / Network):** The bookmark script leaves **`org.gnome.desktop.privacy remember-recent-files`** at **`true`** so **Recent** stays in the sidebar (GNOME-wide recent tracking on). To hide **Recent** again and reduce tracking, run **`NAUTILUS_DISABLE_SYSTEM_RECENT=1`** when invoking **`install-nautilus-sidebar-bookmarks.sh`**, or:

```bash
gsettings set org.gnome.desktop.privacy remember-recent-files false
```

**Starred** and **Network** still have no stable **`gsettings`** toggle in Files **50**.

**Splitter above pinned mounts (below XDG bookmarks):** Adds **`border-top`** on the **first** pinned-mount row (between Documents…Templates and **Backup/Data500**). Selectors include **`.nautilus-window`** (matches Quantum Moon’s Nautilus CSS) and **`window.org-gnome-Nautilus`**, with **`!important`** so the line shows over theme overrides. **`nth-last-child(N)`** uses **`N = (mount bookmarks) + (tail)`**; default **`NAUTILUS_SIDEBAR_TAIL_ROWS=1`** for rows below mounts (e.g. **Other Locations**). Tweak **`0`** / **`2`** if misaligned. Block is in **`~/.config/gtk-4.0/gtk.css`** between **`/* BEGIN caelestia-nautilus-sidebar */`** markers. Requires GTK **color-mix**.

**Volumes / “Other locations”:** **`caelestia/scripts/nautilus-wrap.sh`** appends **`GNOME`** to **`XDG_CURRENT_DESKTOP`** when launching Nautilus so GVfs integration behaves like on a GNOME session. Restart Files after updates (**`nautilus -q`**).

Refresh bookmarks, splitter CSS, icons, and prefs:

```bash
/path/to/Quantum-Moon/scripts/install-nautilus-sidebar-bookmarks.sh
```

Rewrite bookmarks from scratch:

```bash
NAUTILUS_BOOKMARKS_FORCE=1 /path/to/Quantum-Moon/scripts/install-nautilus-sidebar-bookmarks.sh
```

**Packages:** **`install-caelestia.sh`** pulls **`gvfs-smb`** and **`gvfs-nfs`** as optional backends (**`|| true`**). **`gvfs`** / **`udisks2`** should stay installed; user GVfs daemons should be active (**`systemctl --user status gvfs-daemon`**).

---

## Bar VPN shield (nmcli)

Quantum Moon adds a **shield** icon on the Caelestia bar (under ethernet). It toggles an **NetworkManager** profile via **`nmcli`**. Connection names live in **`~/.config/caelestia/bar-vpn.json`** — **not** in **`shell.json`** (Caelestia rewrites **`shell.json`** from the control center and drops unknown keys such as **`bar.vpn`**).

**1. Create or update VPN config** (from the Quantum Moon clone root):

```bash
/path/to/Quantum-Moon/caelestia/scripts/init-shell-vpn-local.sh <nmcli_connection_id> ["Display name"]
```

Example (use the id from **`nmcli -t -f NAME connection show`**):

```bash
/path/to/Quantum-Moon/caelestia/scripts/init-shell-vpn-local.sh my_vpn "My VPN"
```

This writes **`caelestia/shell-vpn.local.json`** (gitignored) and installs **`~/.config/caelestia/bar-vpn.json`**, then restarts the shell.

Overwrite an existing clone-local file:

```bash
FORCE=1 /path/to/Quantum-Moon/caelestia/scripts/init-shell-vpn-local.sh my_vpn "My VPN"
```

Re-install only **`bar-vpn.json`** after editing **`shell-vpn.local.json`**:

```bash
/path/to/Quantum-Moon/caelestia/scripts/merge-shell-vpn-local.sh
```

Check runtime config (this is what the shield uses):

```bash
jq . ~/.config/caelestia/bar-vpn.json
```

**`jq '.bar.vpn' ~/.config/caelestia/shell.json`** will stay **`null`** — that is expected.

Optional environment variables instead of arguments: **`VPN_CONNECTION_NAME`**, **`VPN_DISPLAY_NAME`**.

**2. NMCLI profile** must exist before the shield can connect. Import/setup is separate (e.g. OpenVPN file + **`nmcli connection import`**). List profiles:

```bash
nmcli -t -f NAME connection show
```

**3. After pulling Quantum Moon** (Quickshell patches changed): re-apply patches and refresh VPN config:

```bash
/path/to/Quantum-Moon/scripts/rebuild-caelestia-quickshell.sh
/path/to/Quantum-Moon/caelestia/scripts/merge-shell-vpn-local.sh
```

Fresh **`install-caelestia-overlays.sh`** runs the merge automatically when **`shell-vpn.local.json`** exists.

**4. Hide the shield:** set **`"enabled": false`** in **`~/.config/caelestia/bar-vpn.json`**, or **`bar.status.showVpn`** to **`false`** in **`shell.json`**, then restart the shell (**Ctrl+Super+Alt+R**).

Templates: **`caelestia/shell-vpn.local.json.example`**, **`caelestia/bar-vpn.json.example`**.

---

## Further reading

- [Quantum Moon](https://github.com/atlazlp/Quantum-Moon) (this theme’s source)
- [Caelestia dots](https://github.com/caelestia-dots/caelestia)
- [Caelestia shell (Quickshell)](https://github.com/caelestia-dots/shell)
- [Hyprland wiki](https://wiki.hyprland.org/)
