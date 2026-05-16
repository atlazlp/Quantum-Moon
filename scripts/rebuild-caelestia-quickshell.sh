#!/usr/bin/env bash
set -euo pipefail
# Copy Quantum Moon's patches/quickshell-caelestia into ~/.config/quickshell/caelestia (and nested
# ~/.config/quickshell/caelestia/caelestia if present), then restart the Caelestia Quickshell session.
# Use after editing QML under patches/quickshell-caelestia/ — a plain shell reload does not read the git tree.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="${ROOT}/patches/quickshell-caelestia"
DST="${HOME}/.config/quickshell/caelestia"

if [[ ! -d "$PATCH" ]]; then
  echo "Missing patch directory: $PATCH" >&2
  exit 1
fi

echo "==> Step 1: apply-caelestia-sidebar-screen-patch.sh (explicit install list)"
"${ROOT}/scripts/apply-caelestia-sidebar-screen-patch.sh"

mirror_tree() {
  local dest="$1"
  if [[ ! -d "$dest" ]]; then
    return 0
  fi
  echo "==> Step 2: rsync $PATCH → $dest (modules, services, utils, components)"
  if [[ -f "$PATCH/shell.qml" ]]; then
    install -m644 "$PATCH/shell.qml" "$dest/shell.qml"
  fi
  for sub in modules services utils components; do
    if [[ -d "$PATCH/$sub" && -d "$dest/$sub" ]]; then
      rsync -a "$PATCH/$sub/" "$dest/$sub/"
    fi
  done
}

mirror_tree "$DST"
mirror_tree "$DST/caelestia"

echo "==> Step 3: sanity-check installed ContentWindow (expects launcher mask wiring)"
for base in "$DST" "$DST/caelestia"; do
  f="$base/modules/drawers/ContentWindow.qml"
  if [[ -f "$f" ]]; then
    if grep -q "shellReceivesLauncherPointer" "$f"; then
      echo "    OK $f"
    else
      echo "    WARN: $f missing shellReceivesLauncherPointer (wrong tree or old file?)" >&2
    fi
  fi
done

echo "==> Step 4: restart Quickshell Caelestia (same idea as Hypr Ctrl+Super+Alt+R)"
if command -v qs >/dev/null 2>&1; then
  qs -c caelestia kill 2>/dev/null || true
  sleep 0.45
else
  echo "    (qs not in PATH — kill the shell manually if it is still running)" >&2
fi

if ! command -v caelestia >/dev/null 2>&1; then
  echo "caelestia not in PATH; run: caelestia shell -d" >&2
  exit 1
fi

echo "==> Step 5: verify shell.qml loads (catch QML errors before background start)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
timeout 6 qs -c caelestia 2>&1 | tee "$log" >/dev/null || true
if grep -q "ERROR:" "$log"; then
  echo "ERROR: Quickshell failed to load config:" >&2
  grep "ERROR:" "$log" >&2 || true
  exit 1
fi
qs -c caelestia kill 2>/dev/null || true
sleep 0.35

caelestia shell -d &
sleep 1.5
if qs -c caelestia list 2>&1 | grep -qi "running"; then
  echo "    Caelestia shell is running."
else
  echo "ERROR: shell did not stay up; run: qs -c caelestia 2>&1 | head -40" >&2
  exit 1
fi

echo "Done."
