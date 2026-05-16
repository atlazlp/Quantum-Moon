#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TARGET="${HOME}/.config/caelestia/shell.json"

command -v jq >/dev/null 2>&1 || { echo "needs jq" >&2; exit 1; }
[[ -f "${TARGET}" ]] || { echo "missing ${TARGET}" >&2; exit 1; }

tmp="$(mktemp)"

jq '
  if (.bar.entries | type) == "array" then
    .bar.entries |= map(select((.id // "") != "quantumMoon"))
  else . end
' "${TARGET}" >"${tmp}"

mv "${tmp}" "${TARGET}"
echo "Updated ${TARGET}: removed quantumMoon from bar.entries if present (widget is top-right hover, not the bar)."
