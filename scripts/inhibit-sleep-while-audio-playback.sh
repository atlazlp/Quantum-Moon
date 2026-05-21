#!/usr/bin/env sh
set -eu

poll_s="${INHIBIT_AUDIO_POLL_SEC:-4}"
rtdir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
marker="${CAELESTIA_AUDIO_IDLE_MARKER:-$rtdir/caelestia-audio-playback.active}"
inhibit_pidfile="${CAELESTIA_AUDIO_INHIBIT_PID:-$rtdir/caelestia-audio-inhibit.pid}"

have_active_sink_input() {
	command -v pactl >/dev/null 2>&1 || return 1
	pactl list sink-inputs 2>/dev/null | awk '
		/^Sink Input #/ {
			if (blk && cork == 0 && mute == 0) found = 1
			blk = 1
			cork = 1
			mute = 0
			next
		}
		blk && /^$/ {
			if (cork == 0 && mute == 0) found = 1
			blk = 0
			next
		}
		blk && /^[[:space:]]*Corked:/ { cork = ($2 == "yes" ? 1 : 0); next }
		blk && /^[[:space:]]*Mute:/ { mute = ($2 == "yes" ? 1 : 0); next }
		END {
			if (blk && cork == 0 && mute == 0) found = 1
			exit(found ? 0 : 1)
		}
	'
}

command -v pactl >/dev/null 2>&1 || exit 0

have_systemd_inhibit=0
if command -v systemd-inhibit >/dev/null 2>&1; then
	have_systemd_inhibit=1
fi

inh_pid=""
cleanup() {
	if [ -n "${inh_pid}" ]; then
		kill "${inh_pid}" 2>/dev/null || true
	fi
	rm -f "$marker" "$inhibit_pidfile" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

while :; do
	if have_active_sink_input; then
		touch "$marker" 2>/dev/null || true
		if [ "$have_systemd_inhibit" -eq 1 ]; then
			if [ -z "${inh_pid}" ] || ! kill -0 "${inh_pid}" 2>/dev/null; then
				systemd-inhibit \
					--what=sleep:idle:handle-lid-switch \
					--who=audio-playback \
					--why="Active Pulse/PipeWire playback" \
					--mode=block \
					sleep infinity &
				inh_pid=$!
				echo "${inh_pid}" >"${inhibit_pidfile}" 2>/dev/null || true
			fi
		fi
	else
		rm -f "$marker" "${inhibit_pidfile}" 2>/dev/null || true
		if [ -n "${inh_pid}" ] && kill -0 "${inh_pid}" 2>/dev/null; then
			kill "${inh_pid}" 2>/dev/null || true
		fi
		inh_pid=""
	fi
	sleep "${poll_s}"
done
