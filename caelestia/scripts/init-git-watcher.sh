#!/usr/bin/env bash
# init-git-watcher.sh — Create ~/.config/caelestia/git-watcher.json
#
# Usage:
#   ./init-git-watcher.sh <PAT> [org-url] [project] [my-identity]
#
# Defaults:
#   org-url     https://dev.azure.com/comexport
#   project     Cambio
#   my-identity (empty — enter later via the config UI)
#
# The config file is gitignored and never committed to the repo.

set -euo pipefail

PAT="${1:-}"
ORG_URL="${2:-https://dev.azure.com/comexport}"
PROJECT="${3:-Cambio}"
MY_IDENTITY="${4:-}"

if [[ -z "$PAT" ]]; then
    echo "Usage: $0 <PAT> [org-url] [project] [my-identity]" >&2
    echo "" >&2
    echo "  PAT          Your Azure DevOps Personal Access Token" >&2
    echo "               Required scopes: Code (Read), Graph (Read)" >&2
    echo "  org-url      Organization base URL  (default: https://dev.azure.com/comexport)" >&2
    echo "  project      Project name           (default: Cambio)" >&2
    echo "  my-identity  Your email / UPN       (used for mention/comment detection)" >&2
    exit 1
fi

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/caelestia"
CONFIG_FILE="$CONFIG_DIR/git-watcher.json"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" <<JSON
{
  "enabled": true,
  "pat": "$PAT",
  "organizationUrl": "$ORG_URL",
  "project": "$PROJECT",
  "myIdentity": "$MY_IDENTITY",
  "pollIntervalSeconds": 60,
  "ignoredRepos": [],
  "colors": {
    "overdue": "#ff9500",
    "mention": "#e53935"
  },
  "notifications": {
    "newPr": true,
    "overdueMinutes": 60,
    "prComment": true,
    "prMention": true
  }
}
JSON

chmod 600 "$CONFIG_FILE"
echo "GitWatcher config written to $CONFIG_FILE"
echo "Reload the shell or run: kill -HUP \$(cat ~/.local/state/caelestia/git-watcher.pid)"
