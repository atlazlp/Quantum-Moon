#!/usr/bin/env bash
set -euo pipefail

ACTIVE_MARKER="${XDG_RUNTIME_DIR:-/tmp}/caelestia-game-mode.active"
QM_ROOT_FILE="${HOME}/.config/caelestia/quantum-moon-root"

stop_center_video() {
	local qm
	[[ -f "$QM_ROOT_FILE" ]] || return 0
	read -r qm <"$QM_ROOT_FILE" || return 0
	[[ -n "${qm}" && -f "${qm}/scripts/qm-video-lib.sh" ]] || return 0
	# shellcheck source=/dev/null
	source "${qm}/scripts/qm-video-lib.sh"
	qm_video_stop
}

game_mode_stop() {
	touch "$ACTIVE_MARKER"
	stop_center_video
}

game_mode_start() {
	rm -f "$ACTIVE_MARKER"
}

case "${1:-}" in
stop) game_mode_stop ;;
start) game_mode_start ;;
*)
	echo "usage: $0 stop|start" >&2
	exit 1
	;;
esac
