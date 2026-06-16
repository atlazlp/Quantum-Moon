#!/usr/bin/env bash
set -euo pipefail

submap="${1:?submap name required}"

class="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')"
if [[ "${class}" == steam_app_* ]]; then
  exit 0
fi

hyprctl dispatch submap "${submap}"
