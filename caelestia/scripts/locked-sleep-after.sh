#!/usr/bin/env bash
set -eu

RT="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${RT}/caelestia-locked-sleep.pid"
ARM="${RT}/caelestia-locked-sleep.arm"
WAS_ARMED="${RT}/caelestia-locked-sleep.was-armed"
DELAY_FILE="${RT}/caelestia-locked-sleep.delay"
GRACE_UNTIL="${RT}/caelestia-resume-grace.until"
QS="${QS:-qs}"
AUDIO_MARKER="${RT}/caelestia-audio-playback.active"
AUDIO_INHIBIT_PID="${RT}/caelestia-audio-inhibit.pid"
RESUME_GRACE_SEC="${CAELESTIA_RESUME_GRACE_SEC:-300}"

release_audio_sleep_block() {
	rm -f "${AUDIO_MARKER}" 2>/dev/null || true
	if [[ -f "${AUDIO_INHIBIT_PID}" ]]; then
		kill "$(<"${AUDIO_INHIBIT_PID}")" 2>/dev/null || true
		rm -f "${AUDIO_INHIBIT_PID}"
	fi
	pkill -f 'systemd-inhibit.*--who=audio-playback' 2>/dev/null || true
}

within_resume_grace() {
	[[ -f "${GRACE_UNTIL}" ]] || return 1
	local until now
	until="$(<"${GRACE_UNTIL}")"
	now="$(date +%s)"
	[[ "${now}" -lt "${until}" ]]
}

set_resume_grace() {
	local grace="${1:-${RESUME_GRACE_SEC}}"
	date -d "+${grace} seconds" +%s >"${GRACE_UNTIL}" 2>/dev/null \
		|| echo $(( $(date +%s) + grace )) >"${GRACE_UNTIL}"
}

disarm() {
	if [[ -f "${PIDFILE}" ]]; then
		kill "$(<"${PIDFILE}")" 2>/dev/null || true
		rm -f "${PIDFILE}"
	fi
	rm -f "${ARM}"
}

is_locked() {
	command -v "${QS}" >/dev/null 2>&1 \
		&& "${QS}" -c caelestia ipc call lock isLocked 2>/dev/null | grep -qi true
}

saved_delay() {
	if [[ -f "${DELAY_FILE}" ]]; then
		local d
		d="$(<"${DELAY_FILE}")"
		[[ -n "${d}" && "${d}" -gt 0 ]] && echo "${d}" && return 0
	fi
	echo 300
}

arm() {
	delay="${1:-300}"
	disarm
	echo "${delay}" >"${DELAY_FILE}"
	date +%s >"${ARM}"
	(
		sleep "${delay}"
		[[ -f "${ARM}" ]] || exit 0
		within_resume_grace && exit 0
		if is_locked; then
			release_audio_sleep_block
			loginctl suspend 2>/dev/null || systemctl suspend
		fi
	) &
	echo $! >"${PIDFILE}"
}

on_suspend() {
	if [[ -f "${ARM}" ]]; then
		echo 1 >"${WAS_ARMED}"
	else
		rm -f "${WAS_ARMED}"
	fi
	disarm
}

on_resume() {
	set_resume_grace "${RESUME_GRACE_SEC}"
	[[ -f "${WAS_ARMED}" ]] || return 0
	rm -f "${WAS_ARMED}"
	within_resume_grace || true
	if is_locked; then
		arm "$(saved_delay)"
	fi
}

case "${1:-}" in
arm) arm "${2:-300}" ;;
disarm) disarm ;;
on-suspend) on_suspend ;;
on-resume) on_resume ;;
*) echo "usage: $0 arm|disarm|on-suspend|on-resume [seconds]" >&2; exit 1 ;;
esac
