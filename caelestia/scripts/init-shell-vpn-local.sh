#!/usr/bin/env bash
set -euo pipefail

CAE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL="${CAE}/shell-vpn.local.json"
MERGE="${CAE}/scripts/merge-shell-vpn-local.sh"

usage() {
  cat <<'EOF'
Usage: init-shell-vpn-local.sh <nmcli_connection_id> [display_name]

Creates caelestia/shell-vpn.local.json (gitignored), merges into
~/.config/caelestia/shell.json, and removes stale CmxVpn.qml if present.

Environment (optional):
  VPN_CONNECTION_NAME   nmcli profile id (same as first argument)
  VPN_DISPLAY_NAME      label in toasts (defaults to connection id)
  FORCE=1               overwrite an existing shell-vpn.local.json

Example:
  ./caelestia/scripts/init-shell-vpn-local.sh my_vpn "Work VPN"
EOF
}

connection="${1:-${VPN_CONNECTION_NAME:-}}"
display="${2:-${VPN_DISPLAY_NAME:-}}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "${connection}" ]]; then
  usage >&2
  echo >&2
  echo "Error: pass <nmcli_connection_id> or set VPN_CONNECTION_NAME." >&2
  exit 1
fi

if [[ -z "${display}" ]]; then
  display="${connection}"
fi

if [[ -f "${LOCAL}" && "${FORCE:-0}" != "1" ]]; then
  echo "Already exists: ${LOCAL} (set FORCE=1 to overwrite)." >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "init-shell-vpn-local: needs jq" >&2; exit 1; }

jq -n \
  --arg connection "${connection}" \
  --arg display "${display}" \
  '{
    bar: {
      vpn: {
        enabled: true,
        connectionName: $connection,
        displayName: $display
      },
      status: {
        showVpn: true
      }
    }
  }' >"${LOCAL}"
chmod 600 "${LOCAL}"
echo "Wrote ${LOCAL}"

if [[ -x "${MERGE}" ]]; then
  "${MERGE}" "${CAE}"
fi

QS="${HOME}/.config/quickshell/caelestia"
rm -f "${QS}/services/CmxVpn.qml" "${QS}/caelestia/services/CmxVpn.qml" 2>/dev/null || true

if command -v qs >/dev/null 2>&1; then
  qs -c caelestia kill 2>/dev/null || true
  sleep 0.35
fi
if command -v caelestia >/dev/null 2>&1; then
  caelestia shell -d >/dev/null 2>&1 &
  echo "Restarted Caelestia shell (shield uses bar.vpn from shell.json)."
else
  echo "Restart the shell when ready: Ctrl+Super+Alt+R or caelestia shell -d"
fi
