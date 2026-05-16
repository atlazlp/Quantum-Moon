#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT}/backup"
STAMP="$(date +%Y%m%d-%H%M%S)"
ZIP="${OUT_DIR}/quantum-moon-baseline-${STAMP}.zip"
TMP="$(cd "$(mktemp -d)" && pwd)"

cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

mkdir -p "${OUT_DIR}" "${TMP}/ARCHIVE-EXTRA"

{
  echo "created_local=${STAMP}"
  echo "repo=${ROOT}"
  if [[ -d "${ROOT}/.git" ]]; then
    echo "git_commit=$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
  fi
  if [[ -d "${HOME}/.local/share/caelestia/.git" ]]; then
    echo "upstream_caelestia=$(git -C "${HOME}/.local/share/caelestia" rev-parse HEAD 2>/dev/null || echo unknown)"
  else
    echo "caelestia_upstream_dir=${HOME}/.local/share/caelestia"
  fi
  echo "hypr_config_symlink=$(readlink "${HOME}/.config/hypr" 2>/dev/null || echo none)"
  echo "hypr_config_resolved=$(readlink -f "${HOME}/.config/hypr" 2>/dev/null || echo missing)"
} >"${TMP}/ARCHIVE-EXTRA/REVISION.txt"

{
  echo "Committed overrides reference asset paths under ~/Documents or elsewhere."
  echo "Restore LIVE-CONFIG and LIVE-QUICKSHELL after unpack if you need this machine state."
} >"${TMP}/ARCHIVE-EXTRA/PATHS-NOTES.txt"

mkdir -p "${TMP}/ARCHIVE-EXTRA/LIVE-CONFIG/caelestia"
for f in hypr-user.conf hypr-vars.conf shell.json; do
  [[ -f "${HOME}/.config/caelestia/${f}" ]] && cp -a "${HOME}/.config/caelestia/${f}" "${TMP}/ARCHIVE-EXTRA/LIVE-CONFIG/caelestia/"
done
[[ -d "${HOME}/.config/caelestia/monitors" ]] && cp -a "${HOME}/.config/caelestia/monitors" "${TMP}/ARCHIVE-EXTRA/LIVE-CONFIG/caelestia/"
[[ -f "${HOME}/.config/hypr/hyprpaper.conf" ]] && mkdir -p "${TMP}/ARCHIVE-EXTRA/LIVE-CONFIG/hypr" && cp -a "${HOME}/.config/hypr/hyprpaper.conf" "${TMP}/ARCHIVE-EXTRA/LIVE-CONFIG/hypr/"

if [[ -d "${HOME}/.config/quickshell/caelestia" ]]; then
  mkdir -p "${TMP}/ARCHIVE-EXTRA"
  cp -a "${HOME}/.config/quickshell/caelestia" "${TMP}/ARCHIVE-EXTRA/LIVE-QUICKSHELL-caelestia"
fi

if [[ -d "${ROOT}/.git" ]]; then
  git -C "${ROOT}" archive --format=tar HEAD | tar -C "${TMP}" -xf -
else
  mkdir -p "${TMP}/repo-copy"
  cp -a "${ROOT}/." "${TMP}/repo-copy/"
fi

if [[ -d "${ROOT}/.git" ]]; then
  git -C "${ROOT}" bundle create "${TMP}/ARCHIVE-EXTRA/git-all.bundle" --all 2>/dev/null || true
fi

if command -v zip >/dev/null 2>&1; then
  (
    cd "${TMP}"
    zip -qr "${ZIP}" .
  )
  echo "Wrote ${ZIP}"
else
  ARCHIVE="${OUT_DIR}/quantum-moon-baseline-${STAMP}.tar.gz"
  tar -C "${TMP}" -czf "${ARCHIVE}" .
  echo "zip not found; wrote ${ARCHIVE}"
fi
