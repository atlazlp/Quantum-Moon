#!/usr/bin/env bash
set -eu

RT="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${RT}/caelestia-locked-sleep.pid"
ARM="${RT}/caelestia-locked-sleep.arm"
QS="${QS:-qs}"
AUDIO_MARKER="${RT}/caelestia-audio-playback.active"
AUDIO_INHIBIT_PID="${RT}/caelestia-audio-inhibit.pid"

release_audio_sleep_block() {
	rm -f "${AUDIO_MARKER}" 2>/dev/null || true
	if [[ -f "${AUDIO_INHIBIT_PID}" ]]; then
		kill "$(<"${AUDIO_INHIBIT_PID}")" 2>/dev/null || true
		rm -f "${AUDIO_INHIBIT_PID}"
	fi
	pkill -f 'systemd-inhibit.*--who=audio-playback' 2>/dev/null || true
}

disarm() {
	if [[ -f "${PIDFILE}" ]]; then
		kill "$(<"${PIDFILE}")" 2>/dev/null || true
		rm -f "${PIDFILE}"
	fi
	rm -f "${ARM}"
}

arm() {
	delay="${1:-300}"
	disarm
	date +%s >"${ARM}"
	(
		sleep "${delay}"
		[[ -f "${ARM}" ]] || exit 0
		if command -v "${QS}" >/dev/null 2>&1 && "${QS}" -c caelestia ipc call lock isLocked 2>/dev/null | grep -qi true; then
			release_audio_sleep_block
			loginctl suspend 2>/dev/null || systemctl suspend
		fi
	) &
	echo $! >"${PIDFILE}"
}

case "${1:-}" in
arm) arm "${2:-300}" ;;
disarm) disarm ;;
*) echo "usage: $0 arm|disarm [seconds]" >&2; exit 1 ;;
esac
