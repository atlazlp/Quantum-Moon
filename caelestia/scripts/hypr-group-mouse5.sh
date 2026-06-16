#!/usr/bin/env bash
set -euo pipefail

aw="$(hyprctl activewindow -j 2>/dev/null)" || exit 0

# Respect the Steam-game block: do nothing if a Steam game is focused.
class="$(jq -r '.class // empty' <<<"${aw}" 2>/dev/null || echo "")"
if [[ "${class}" == steam_app_* ]]; then
  exit 0
fi

count="$(jq -r 'if (.grouped | type) == "array" then (.grouped | length) else 0 end' <<<"${aw}" 2>/dev/null || echo 0)"

if [[ "${count}" -gt 0 ]]; then
  hyprctl dispatch moveoutofgroup
else
  hyprctl dispatch togglegroup
fi
