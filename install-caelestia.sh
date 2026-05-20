#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="${HOME}/.local/share/caelestia"
YAY="${YAY:-yay}"

echo "This installs Caelestia from ${UPSTREAM} (AUR meta in that repo) and symlinks ~/.config/hypr."
echo "You need network access and sudo when pacman installs repo packages."
echo

mkdir -p "${HOME}/.local/share"
if [[ ! -d "${UPSTREAM}/.git" ]]; then
  git clone --depth 1 https://github.com/caelestia-dots/caelestia.git "${UPSTREAM}"
fi

cd "${UPSTREAM}"
${YAY} -Bi . --noconfirm --needed

if [[ -L "${HOME}/.config/hypr" ]]; then
  rm "${HOME}/.config/hypr"
elif [[ -e "${HOME}/.config/hypr" ]]; then
  mv "${HOME}/.config/hypr" "${HOME}/.config/hypr.bak.$(date +%s)"
fi

ln -sfn "${UPSTREAM}/hypr" "${HOME}/.config/hypr"
chmod u+x "${HOME}/.config/hypr/scripts/wsaction.fish"

mkdir -p "${HOME}/.config/hypr" "${HOME}/.config/caelestia/scripts"
install -m755 "${ROOT}/scripts/inhibit-sleep-while-audio-playback.sh" "${HOME}/.config/caelestia/scripts/inhibit-sleep-while-audio-playback.sh"
install -m755 "${ROOT}/scripts/audio-toggle-analog-output.sh" "${HOME}/.config/caelestia/scripts/audio-toggle-analog-output.sh"
mkdir -p "${HOME}/.config/wireplumber/wireplumber.conf.d"
install -m644 "${ROOT}/config/wireplumber/wireplumber.conf.d/51-alsa-analog-ports.conf" "${HOME}/.config/wireplumber/wireplumber.conf.d/51-alsa-analog-ports.conf"
install -m755 "${ROOT}/caelestia/scripts/cursor-clean.sh" "${HOME}/.config/caelestia/scripts/cursor-clean.sh"
install -m755 "${ROOT}/caelestia/scripts/nautilus-wrap.sh" "${HOME}/.config/caelestia/scripts/nautilus-wrap.sh"
install -m644 "${ROOT}/caelestia/hypr-user.conf" "${HOME}/.config/caelestia/hypr-user.conf"
if [[ ! -f "${HOME}/.config/caelestia/hypr-user-local.conf" ]]; then
  install -m644 "${ROOT}/caelestia/hypr-user-local.conf" "${HOME}/.config/caelestia/hypr-user-local.conf"
fi
install -m644 "${ROOT}/caelestia/hypr-vars.conf" "${HOME}/.config/caelestia/hypr-vars.conf"
install -m644 "${ROOT}/caelestia/hypr-env-qt.conf" "${HOME}/.config/caelestia/hypr-env-qt.conf"
install -m644 "${ROOT}/caelestia/shell.json" "${HOME}/.config/caelestia/shell.json"
if [[ -d "${ROOT}/caelestia/assets" ]]; then
  mkdir -p "${HOME}/.config/caelestia/assets"
  cp -a "${ROOT}/caelestia/assets/." "${HOME}/.config/caelestia/assets/"
fi
install -m644 "${ROOT}/caelestia/hyprpaper.conf" "${HOME}/.config/hypr/hyprpaper.conf"
if [[ -d "${ROOT}/caelestia/monitors" ]]; then
  mkdir -p "${HOME}/.config/caelestia/monitors"
  cp -rn "${ROOT}/caelestia/monitors/." "${HOME}/.config/caelestia/monitors/" 2>/dev/null || true
fi

if [[ ! -f "${HOME}/.config/caelestia/nautilus-sidebar-extra" ]] && [[ -f "${ROOT}/caelestia/nautilus-sidebar-extra" ]]; then
  install -m644 "${ROOT}/caelestia/nautilus-sidebar-extra" "${HOME}/.config/caelestia/nautilus-sidebar-extra"
fi
if [[ ! -f "${HOME}/.config/caelestia/nautilus-drive-icons" ]] && [[ -f "${ROOT}/caelestia/nautilus-drive-icons" ]]; then
  install -m644 "${ROOT}/caelestia/nautilus-drive-icons" "${HOME}/.config/caelestia/nautilus-drive-icons"
fi

${YAY} -S --needed --noconfirm polkit-gnome foot kitty hyprpaper mpvpaper nautilus qt6ct frameworkintegration xdg-user-dirs gvfs-smb gvfs-nfs hyprresume || true

xdg-user-dirs-update 2>/dev/null || true
"${ROOT}/scripts/install-nautilus-sidebar-bookmarks.sh"

mkdir -p "${HOME}/.local/state/caelestia"
if [[ ! -f "${HOME}/.local/state/caelestia/scheme.json" ]]; then
  caelestia scheme set -n shadotheme || true
fi

hyprctl reload 2>/dev/null || true
echo "Done. Log out and back in if the shell or Hyprland did not pick everything up."
echo "For per-monitor sidebar (center only): ${ROOT}/scripts/apply-caelestia-sidebar-screen-patch.sh"
echo "Outer Wilds Quantum Moon: ${ROOT}/docs/installation-tutorial.md"
