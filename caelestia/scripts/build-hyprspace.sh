#!/usr/bin/env bash
set -euo pipefail
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia/hyprspace-git"
REPO="https://github.com/KZDKM/Hyprspace"
RENDER="${ROOT}/src/Render.cpp"

cat <<'WARN' >&2
WARNING: Hyprspace builds for Hyprland 0.54.3 but has been observed to SEGV at runtime
(in plugin onMouseButton — see ~/.cache/hyprland/hyprlandCrashReport*.txt).
Do NOT "hyprctl plugin load" this .so on 0.54.3 unless you are debugging upstream.
Super+D / bar overview use Caelestia window picker without Hyprspace.
WARN

mkdir -p "$(dirname "$ROOT")"
if [[ ! -d "${ROOT}/.git" ]]; then
  git clone --depth 1 "$REPO" "$ROOT"
else
  git -C "$ROOT" pull --ff-only || true
fi

if ! grep -qF '#include <climits>' "$RENDER"; then
  sed -i '/#include <hyprutils\/utils\/ScopeGuard.hpp>/a#include <climits>' "$RENDER"
fi

make -C "$ROOT" all

so="$(readlink -f "${ROOT}/Hyprspace.so")"
[[ -f "$so" ]] || { echo "missing $so" >&2; exit 1; }
echo "Built (unsafe on 0.54.3): $so" >&2
echo "To keep it off the autoload path:  mv \"$so\" \"${so}.disabled\""
