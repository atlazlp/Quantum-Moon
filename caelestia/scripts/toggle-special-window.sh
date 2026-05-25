#!/usr/bin/env bash
# Move the focused window into special:special, or back to the monitor's active workspace.
set -euo pipefail

target="${QM_SPECIAL_WS:-special:special}"
short="${target#special:}"

json=$(hyprctl activewindow -j)
addr=$(jq -r '.address // empty' <<<"$json")
[[ -n "$addr" && "$addr" != "null" ]] || exit 0

ws=$(jq -r '.workspace.name // empty' <<<"$json")
mon=$(hyprctl monitors -j | jq -c '.[] | select(.focused)')

if [[ "$ws" == special:* ]]; then
  active_name=$(jq -r '.activeWorkspace.name // "1"' <<<"$mon")
  hyprctl dispatch movetoworkspacesilent "name:${active_name},address:${addr}"
  special_open=$(jq -r '.specialWorkspace.name // empty' <<<"$mon")
  if [[ -n "$special_open" ]]; then
    hyprctl dispatch togglespecialworkspace "${special_open#special:}"
  fi
else
  hyprctl dispatch movetoworkspacesilent "${target},address:${addr}"
  special_open=$(jq -r '.specialWorkspace.name // empty' <<<"$mon")
  if [[ "$special_open" != "$target" ]]; then
    hyprctl dispatch togglespecialworkspace "$short"
  fi
fi
