#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CAE="${ROOT}/caelestia"
DEST_C="${HOME}/.config/caelestia"
DEST_H="${HOME}/.config/hypr"
STAMP="$(date +%Y%m%d-%H%M%S)"
HOST="$(hostname -s 2>/dev/null || echo host)"

default_backup_root() {
  if [[ -n "${CAELESTIA_OVERLAY_BACKUP_ROOT:-}" ]]; then
    printf '%s' "${CAELESTIA_OVERLAY_BACKUP_ROOT}"
    return
  fi
  if [[ -d /mnt/Backup ]]; then
    printf '%s' "/mnt/Backup"
    return
  fi
  printf ''
}

BACKUP_ROOT="$(default_backup_root)"
[[ -n "${BACKUP_ROOT}" ]] || {
  echo "Set CAELESTIA_OVERLAY_BACKUP_ROOT to your mounted backup directory (e.g. export CAELESTIA_OVERLAY_BACKUP_ROOT=/mnt/Backup)." >&2
  exit 1
}
[[ -d "${BACKUP_ROOT}" ]] || {
  echo "Backup root is not a directory: ${BACKUP_ROOT}" >&2
  exit 1
}

BACKUP_DIR="${BACKUP_ROOT}/caelestia-overlay-backups/${HOST}/${STAMP}"
mkdir -p "${BACKUP_DIR}/caelestia" "${BACKUP_DIR}/hypr"

[[ -d "${CAE}" ]] || { echo "missing ${CAE}" >&2; exit 1; }
[[ -f "${CAE}/hypr-user.conf" ]] || { echo "missing ${CAE}/hypr-user.conf" >&2; exit 1; }
[[ -f "${CAE}/hypr-user-local.conf" ]] || { echo "missing ${CAE}/hypr-user-local.conf" >&2; exit 1; }

{
  echo "stamp=${STAMP}"
  echo "host=${HOST}"
  echo "backup_root=${BACKUP_ROOT}"
  echo "user=${USER}"
  echo "home=${HOME}"
  echo "reason=pre-install-caelestia-overlays"
} >"${BACKUP_DIR}/MANIFEST.txt"

any=0
for f in hypr-user.conf hypr-user-local.conf hypr-vars.conf shell.json hyprresume.toml; do
  if [[ -f "${DEST_C}/${f}" ]]; then
    cp -a "${DEST_C}/${f}" "${BACKUP_DIR}/caelestia/${f}"
    any=1
  fi
done
if [[ -d "${DEST_C}/monitors" ]]; then
  cp -a "${DEST_C}/monitors" "${BACKUP_DIR}/caelestia/"
  any=1
fi
if [[ -f "${DEST_H}/hyprpaper.conf" ]]; then
  cp -a "${DEST_H}/hyprpaper.conf" "${BACKUP_DIR}/hypr/hyprpaper.conf"
  any=1
fi
if [[ "${any}" -eq 0 ]]; then
  echo "(no existing files under ${DEST_C} or ${DEST_H}/hyprpaper.conf to back up)" >>"${BACKUP_DIR}/MANIFEST.txt"
fi

echo "Backed up prior configs to ${BACKUP_DIR}"

mkdir -p "${DEST_C}" "${DEST_C}/scripts" "${DEST_H}"
install -m755 "${ROOT}/scripts/inhibit-sleep-while-audio-playback.sh" "${DEST_C}/scripts/inhibit-sleep-while-audio-playback.sh"
install -m755 "${ROOT}/scripts/audio-toggle-analog-output.sh" "${DEST_C}/scripts/audio-toggle-analog-output.sh"
install -m755 "${ROOT}/scripts/audio-reload-mic.sh" "${DEST_C}/scripts/audio-reload-mic.sh"
install -m755 "${ROOT}/scripts/audio-setup-analog-mic.sh" "${DEST_C}/scripts/audio-setup-analog-mic.sh"
mkdir -p "${HOME}/.config/wireplumber/wireplumber.conf.d"
install -m644 "${ROOT}/config/wireplumber/wireplumber.conf.d/51-alsa-analog-ports.conf" "${HOME}/.config/wireplumber/wireplumber.conf.d/51-alsa-analog-ports.conf"
install -m644 "${ROOT}/config/wireplumber/wireplumber.conf.d/52-analog-mic-echo-cancel.conf" "${HOME}/.config/wireplumber/wireplumber.conf.d/52-analog-mic-echo-cancel.conf"
mkdir -p "${HOME}/.config/systemd/user"
install -m644 "${ROOT}/config/systemd/user/audio-analog-mic-setup.service" "${HOME}/.config/systemd/user/audio-analog-mic-setup.service"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now audio-analog-mic-setup.service 2>/dev/null || true
for s in cursor-clean.sh workspace-overview-toggle.sh window-alt-tab-cycle.sh window_menu.py hypr-focus-window.sh activity-monitor.sh build-hyprspace.sh hypr-group-mouse5.sh hyprresume-save.sh proton-hide-ghost-windows.sh locked-sleep-after.sh suspend-resume-watch.sh toggle-special-window.sh; do
  if [[ -f "${CAE}/scripts/${s}" ]]; then
    install -m755 "${CAE}/scripts/${s}" "${DEST_C}/scripts/${s}"
  fi
done
rm -f "${DEST_C}/scripts/window-picker-fuzzel.sh" "${DEST_C}/scripts/qm-launcher-log.sh"
install -m644 "${CAE}/hypr-user.conf" "${DEST_C}/hypr-user.conf"
if [[ -x "${CAE}/scripts/gen-hypr-launcher-interrupts.sh" ]]; then
  "${CAE}/scripts/gen-hypr-launcher-interrupts.sh" "${DEST_C}/hypr-launcher-interrupts.conf"
else
  echo "WARN: missing ${CAE}/scripts/gen-hypr-launcher-interrupts.sh (Super chords may open the launcher)" >&2
fi
if [[ ! -f "${DEST_C}/hypr-user-local.conf" ]]; then
  install -m644 "${CAE}/hypr-user-local.conf" "${DEST_C}/hypr-user-local.conf"
fi
install -m644 "${CAE}/hypr-vars.conf" "${DEST_C}/hypr-vars.conf"
install -m644 "${CAE}/hypr-env-qt.conf" "${DEST_C}/hypr-env-qt.conf"
install -m644 "${CAE}/hyprresume.toml" "${DEST_C}/hyprresume.toml"
if [[ ! -f "${DEST_C}/shell.json" ]]; then
  install -m644 "${CAE}/shell.json" "${DEST_C}/shell.json"
else
  echo "Keeping existing ${DEST_C}/shell.json (taskbar and per-screen settings preserved)."
fi
if [[ -f "${HOME}/.config/caelestia/quantum-moon-root" ]]; then
  read -r QM < "${HOME}/.config/caelestia/quantum-moon-root" || QM=""
  if [[ -n "${QM}" && -x "${QM}/scripts/qm-apply" ]]; then
    "${QM}/scripts/qm-apply" --persisted 2>/dev/null || true
  else
    install -m644 "${CAE}/hyprpaper.conf" "${DEST_H}/hyprpaper.conf"
  fi
else
  install -m644 "${CAE}/hyprpaper.conf" "${DEST_H}/hyprpaper.conf"
fi
install -m755 "${ROOT}/caelestia/scripts/nautilus-wrap.sh" "${DEST_C}/scripts/nautilus-wrap.sh"
if [[ -d "${CAE}/assets" ]]; then
  mkdir -p "${DEST_C}/assets"
  cp -a "${CAE}/assets/." "${DEST_C}/assets/"
fi

if [[ -d "${CAE}/monitors" ]]; then
  mkdir -p "${DEST_C}/monitors"
  cp -rn "${CAE}/monitors/." "${DEST_C}/monitors/" 2>/dev/null || cp -r --update=none "${CAE}/monitors/." "${DEST_C}/monitors/" 2>/dev/null || true
fi

if [[ ! -f "${DEST_C}/nautilus-sidebar-extra" ]] && [[ -f "${CAE}/nautilus-sidebar-extra" ]]; then
  install -m644 "${CAE}/nautilus-sidebar-extra" "${DEST_C}/nautilus-sidebar-extra"
fi
if [[ ! -f "${DEST_C}/nautilus-drive-icons" ]] && [[ -f "${CAE}/nautilus-drive-icons" ]]; then
  install -m644 "${CAE}/nautilus-drive-icons" "${DEST_C}/nautilus-drive-icons"
fi

if command -v jq >/dev/null 2>&1; then
  "${ROOT}/quantum-moon/scripts/merge-bar-quantum-moon.sh"
  if [[ -x "${CAE}/scripts/merge-shell-vpn-local.sh" ]]; then
    "${CAE}/scripts/merge-shell-vpn-local.sh" "${CAE}"
  fi
else
  echo "jq not found: skipped merge-bar-quantum-moon (install jq, then re-run this script)." >&2
fi

"${ROOT}/scripts/install-nautilus-sidebar-bookmarks.sh"

SCHEME="${XDG_STATE_HOME:-${HOME}/.local/state}/caelestia/scheme.json"
if [[ -f "${SCHEME}" ]]; then
  python3 "${ROOT}/quantum-moon/scripts/qm-sync-file-manager-theme.py" "${SCHEME}" || true
fi

hyprctl reload 2>/dev/null || true
if [[ -f "${HOME}/.config/caelestia/quantum-moon-root" ]]; then
  read -r QM < "${HOME}/.config/caelestia/quantum-moon-root" || QM=""
  if [[ -n "${QM}" && -f "${QM}/scripts/qm-video-sync-from-state" ]]; then
    bash "${QM}/scripts/qm-video-sync-from-state" 2>/dev/null || true
  fi
fi
if pgrep -x hyprpaper >/dev/null 2>&1; then
  hyprctl hyprpaper reload 2>/dev/null || pkill -x hyprpaper 2>/dev/null || true
fi
if ! pgrep -x hyprpaper >/dev/null 2>&1; then
  hyprpaper 2>/dev/null &
fi

if [[ -x "${ROOT}/scripts/apply-caelestia-sidebar-screen-patch.sh" ]]; then
  "${ROOT}/scripts/apply-caelestia-sidebar-screen-patch.sh"
fi

echo "Installed Caelestia overlays from ${CAE} into ${DEST_C} (and hyprpaper into ${DEST_H})."
echo "Restart Caelestia (Ctrl+Super+Alt+R) if the shell was already running."
