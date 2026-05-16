#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/extras/keyd-mouse-thumb-as-meta.conf"
if ! pacman -Q keyd >/dev/null 2>&1; then
	echo "Installing keyd (needs sudo)." >&2
	sudo pacman -S --needed --noconfirm keyd
fi
sudo install -Dm644 "$src" /etc/keyd/99-mouse-thumb-as-meta.conf
sudo systemctl enable --now keyd.service
sudo systemctl restart keyd.service
echo "Installed /etc/keyd/99-mouse-thumb-as-meta.conf and restarted keyd."
