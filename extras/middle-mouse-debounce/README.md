# middle-mouse-debounce

System service that grabs the E-Signal USB gaming mouse, debounces its failing
switches, and re-emits a clean virtual device.

It does two things:

1. **Middle-button debounce** — the middle switch chatters (double-fires); this
   collapses bounce into single clicks.
2. **Thumb-button remap (workaround)** — the mouse4/mouse5 switches also chatter,
   and more importantly Hyprland **0.55.3+** has a regression (merged PR #14633,
   "Aggregate modifier states from all keyboards on focus enter") where
   **mouse-button binds (`bind`/`bindm` on `mouse:NNN`) no longer fire** when
   multiple keyboard HID devices are present — keyboard-key binds bound by
   keycode still work. So the thumb switches are remapped to keyboard keys:
   - mouse4 / BTN_SIDE  → `KEY_F13` → Hyprland `code:191`
   - mouse5 / BTN_EXTRA → `KEY_F14` → Hyprland `code:192`

   `caelestia/hypr-user-local.conf` binds `code:191`/`code:192`. Revert that
   block (and this script's `SIDE_MAP`) to plain `mouse:275/276` once the
   upstream regression is fixed. Tracking: hyprwm/Hyprland #15065 #15068 #15081.

   Note the EV_SYN fix in the script: newer kernels / python-evdev reject
   `EV_SYN` codes when creating a `UInput` device (OSError Errno 22), so it must
   be stripped from the copied capabilities.

`keyd` must stay disabled — its old `mouseback → leftmeta` map conflicts.

## Install

```sh
sudo install -m0755 middle-mouse-debounce /usr/local/bin/middle-mouse-debounce
sudo install -m0644 middle-mouse-debounce.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/middle-mouse-debounce.service.d
sudo install -m0644 override.conf /etc/systemd/system/middle-mouse-debounce.service.d/
sudo systemctl daemon-reload
sudo systemctl enable --now middle-mouse-debounce.service
sudo systemctl disable --now keyd.service   # conflicts; keep disabled
```

Requires `python-evdev`. The `override.conf` keeps the unit retrying instead of
hitting the start-limit when the USB mouse hasn't enumerated yet at early boot.
