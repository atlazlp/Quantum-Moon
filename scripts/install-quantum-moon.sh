#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QM="${REPO}/quantum-moon"
MARKER="${HOME}/.config/caelestia/quantum-moon-root"
BIN="${HOME}/.local/bin"

mkdir -p "${HOME}/.config/caelestia" "${BIN}"
printf '%s\n' "${QM}" >"${MARKER}"
chmod +x "${QM}/scripts/"*

ln -sfn "${QM}/scripts/qm-apply" "${BIN}/qm-apply"
ln -sfn "${QM}/scripts/qm-random" "${BIN}/qm-random"
ln -sfn "${QM}/scripts/qm-init-mvp-assets" "${BIN}/qm-init-mvp-assets"
ln -sfn "${QM}/scripts/qm-video-watch" "${BIN}/qm-video-watch"
ln -sfn "${QM}/scripts/qm-video-restart" "${BIN}/qm-video-restart"

echo "Wrote ${MARKER}"
echo "Symlinked qm-apply, qm-random, qm-init-mvp-assets, qm-video-watch, qm-video-restart into ${BIN}"
