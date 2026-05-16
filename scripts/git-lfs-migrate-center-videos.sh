#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v git-lfs >/dev/null 2>&1; then
  echo "git-lfs is not installed. On Arch / CachyOS:" >&2
  echo "  sudo pacman -S git-lfs" >&2
  exit 1
fi

git lfs install

ATTR='quantum-moon/modes/*/wallpapers/center.mp4'
if ! grep -qF 'wallpapers/center.mp4' .gitattributes 2>/dev/null; then
  git lfs track "$ATTR"
fi

git add .gitattributes

echo "Rewriting git history so center.mp4 files use LFS (required before GitHub push)..."
git lfs migrate import --include="$ATTR" --everything

echo
echo "LFS objects:"
git lfs ls-files

echo
echo "Next: git push -u origin main"
echo "If the remote already has old commits with large blobs, use: git push --force-with-lease origin main"
