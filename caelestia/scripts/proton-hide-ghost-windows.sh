#!/usr/bin/env bash
# Hide Proton/Steam ghost XWayland windows (Wine explorer /desktop, tiny empty-title steam_app_*).
set -uo pipefail

LOCK="${XDG_RUNTIME_DIR:-/tmp}/proton-hide-ghost-windows.lock"
if [[ -f "$LOCK" ]] && kill -0 "$(<"$LOCK")" 2>/dev/null; then
  exit 0
fi
echo $$ >"$LOCK"
trap 'rm -f "$LOCK"' EXIT

while true; do
  hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    klass = (c.get('class') or '').strip()
    if not (klass.startswith('steam_app_') or klass in ('steam', 'steam_proton')):
        continue
    if (c.get('title') or '').strip():
        continue
    w, h = c['size']
    if h <= 30 and w <= 220:
        print(c['address'])
" | while read -r addr; do
    [ -n "$addr" ] && hyprctl dispatch closewindow "address:${addr}" 2>/dev/null || true
  done

  for pid in $(pgrep -f 'explorer\.exe /desktop' 2>/dev/null); do
    cwd=$(readlink -f "/proc/${pid}/cwd" 2>/dev/null || true)
    case "$cwd" in
      */steamapps/compatdata/*/pfx/*) kill "$pid" 2>/dev/null || true ;;
    esac
  done

  sleep 1
done
