#!/usr/bin/env bash
set -euo pipefail

CAE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TARGET="${HOME}/.config/caelestia/shell.json"
LOCAL="${CAE}/shell-vpn.local.json"

command -v jq >/dev/null 2>&1 || { echo "merge-shell-vpn-local: needs jq" >&2; exit 1; }
[[ -f "${LOCAL}" ]] || exit 0
[[ -f "${TARGET}" ]] || { echo "merge-shell-vpn-local: missing ${TARGET}" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
jq -s '.[0] * .[1]' "${TARGET}" "${LOCAL}" >"${tmp}"
install -m644 "${tmp}" "${TARGET}"
echo "Merged bar VPN settings from ${LOCAL} into ${TARGET}."
