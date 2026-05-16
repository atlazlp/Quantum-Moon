#!/usr/bin/env bash
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_saved="$(hyprctl getoption input:follow_mouse -j 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("int",1))' 2>/dev/null || echo 1)"
[[ -z "${_saved}" ]] && _saved=1

restore_follow_mouse() {
  hyprctl keyword input:follow_mouse "${_saved}" >/dev/null 2>&1 || true
}
trap restore_follow_mouse EXIT

hyprctl keyword input:follow_mouse 0 >/dev/null 2>&1 || true

sel=$(
  hyprctl clients -j | python3 "${DIR}/window_menu.py" list | fuzzel -d -p "Windows " --with-nth=2 --accept-nth=1 -R --no-exit-on-keyboard-focus-loss
) || true

[[ -z "${sel}" ]] && exit 0

hyprctl dispatch "focuswindow address:${sel}"
