# middle-mouse-debounce

System service that grabs the E-Signal USB gaming mouse and re-emits a clean
virtual device, debouncing the middle switch (which chatters / double-fires).

The only non-obvious bit is the **EV_SYN fix**: newer kernels / python-evdev
reject `EV_SYN` codes when creating a `UInput` device (OSError Errno 22), so the
script strips `EV_SYN` from the copied capabilities before creating the device.
This is independent of the Hyprland version and must stay, otherwise the service
crash-loops and the middle button double-fires again.

`keyd` should stay disabled — its old `mouseback → leftmeta` map conflicts with
the thumb-button shortcuts.

## Install

```sh
sudo install -m0755 middle-mouse-debounce /usr/local/bin/middle-mouse-debounce
sudo install -m0644 middle-mouse-debounce.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/middle-mouse-debounce.service.d
sudo install -m0644 override.conf /etc/systemd/system/middle-mouse-debounce.service.d/
sudo systemctl daemon-reload
sudo systemctl enable --now middle-mouse-debounce.service
```

Requires `python-evdev`. The `override.conf` keeps the unit retrying instead of
hitting the start-limit when the USB mouse hasn't enumerated yet at early boot.
