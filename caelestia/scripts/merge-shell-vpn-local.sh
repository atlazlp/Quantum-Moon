#!/usr/bin/env bash
set -euo pipefail

CAE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOCAL="${CAE}/shell-vpn.local.json"
TARGET="${HOME}/.config/caelestia/bar-vpn.json"

command -v jq >/dev/null 2>&1 || { echo "merge-shell-vpn-local: needs jq" >&2; exit 1; }
[[ -f "${LOCAL}" ]] || exit 0

mkdir -p "$(dirname "${TARGET}")"
jq '.bar.vpn // empty' "${LOCAL}" >"${TARGET}.tmp"
if [[ ! -s "${TARGET}.tmp" ]]; then
  echo "merge-shell-vpn-local: no .bar.vpn in ${LOCAL}" >&2
  rm -f "${TARGET}.tmp"
  exit 1
fi
install -m600 "${TARGET}.tmp" "${TARGET}"
rm -f "${TARGET}.tmp"
echo "Installed ${TARGET} from ${LOCAL} (Caelestia does not keep bar.vpn inside shell.json)."
