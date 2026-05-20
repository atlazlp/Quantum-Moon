#!/usr/bin/env bash
# Focus a Hyprland window by address, including the correct tab in a window group.
set -euo pipefail

addr="${1:?window address required}"
addr="${addr,,}"
[[ "${addr}" == 0x* ]] || addr="0x${addr}"

hyprctl dispatch "focuswindow address:${addr}" 2>/dev/null || true
sleep 0.08

active="$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' | tr '[:upper:]' '[:lower:]')"
[[ "${active}" == "${addr}" ]] && exit 0

group_len="$(hyprctl clients -j 2>/dev/null | jq -r --arg a "${addr}" '
  .[] | select((.address | ascii_downcase) == $a) | (.grouped | length) // 0
' | head -1)"
group_len="${group_len:-0}"

if [[ "${group_len}" -lt 2 ]]; then
  exit 1
fi

head="$(hyprctl clients -j 2>/dev/null | jq -r --arg a "${addr}" '
  .[] | select((.address | ascii_downcase) == $a) | .grouped[0] // empty
' | head -1 | tr '[:upper:]' '[:lower:]')"

if [[ -n "${head}" ]]; then
  hyprctl dispatch "focuswindow address:${head}" 2>/dev/null || true
  sleep 0.05
  active="$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' | tr '[:upper:]' '[:lower:]')"
  [[ "${active}" == "${addr}" ]] && exit 0
fi

for _ in $(seq 1 "${group_len}"); do
  active="$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' | tr '[:upper:]' '[:lower:]')"
  [[ "${active}" == "${addr}" ]] && exit 0
  hyprctl dispatch changegroupactive f 2>/dev/null || true
  sleep 0.03
done

exit 1
