#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"

overview_all() {
  local o
  o="$(hyprctl dispatch 'overview:toggle all' 2>&1)" || true
  [[ "$o" != *"Invalid dispatcher"* ]]
}

if [[ "$MODE" == "all" ]]; then
  overview_all && exit 0
  if command -v qs >/dev/null 2>&1 && qs -c caelestia ipc call drawers toggle windowPicker >/dev/null 2>&1; then
    exit 0
  fi
  exec "${DIR}/window-picker-fuzzel.sh"
fi

printf 'usage: %s all\n' "$(basename "$0")" >&2
exit 1
