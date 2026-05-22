#!/usr/bin/env bash
# Onboard analog mic (ALC897-class): kill codec loopback + route I/O through WebRTC echo-cancel.
set -euo pipefail

source_regex="${AUDIO_ANALOG_SOURCE_REGEX:-11_00.6.analog-stereo$}"
sink_regex="${AUDIO_ANALOG_SINK_REGEX:-11_00.6.analog-stereo$}"
alsa_card="${AUDIO_ANALOG_ALSA_CARD:-}"
echo_source="${AUDIO_ECHO_SOURCE_NAME:-echo-cancel-source}"
echo_sink="${AUDIO_ECHO_SINK_NAME:-echo-cancel-sink}"
quiet=0

toast_warn() {
	[[ "$quiet" -eq 1 ]] && return 0
	if command -v caelestia >/dev/null 2>&1; then
		caelestia shell toaster warn "Audio" "$1" "" 2>/dev/null || true
	else
		echo "$1" >&2
	fi
}

toast_info() {
	[[ "$quiet" -eq 1 ]] && return 0
	if command -v caelestia >/dev/null 2>&1; then
		caelestia shell toaster info "Audio" "$1" "" 2>/dev/null || true
	else
		echo "$1"
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--quiet|-q) quiet=1 ;;
		-h|--help)
			cat <<'EOF'
Usage: audio-setup-analog-mic.sh [--quiet]

Fixes ALC897 desktop-audio-on-mic bleed:
  - ALSA: disable Front Mic Playback / loopback mixer paths
  - PipeWire: WebRTC echo-cancel on BOTH default mic and default speakers

Echo cancel only works when playback uses echo-cancel-sink (not raw line-out).
Discord must use default I/O or "echo-cancel-source" / "echo-cancel-sink".

Optional kernel fix for TRRS front-panel headsets (reboot):
  sudo install -m644 modprobe snippet, then reboot — see config/modprobe.d/README-alc897.txt
EOF
			exit 0
			;;
		*) toast_warn "Unknown option: $1"; exit 2 ;;
	esac
	shift
done

if ! command -v pactl >/dev/null 2>&1; then
	toast_warn "pactl not installed — mic setup skipped."
	exit 1
fi

find_analog_source() {
	pactl list sources short 2>/dev/null | awk -v re="$source_regex" '$2 ~ re && $2 !~ /\.monitor$/ { print $2; exit }'
}

find_analog_sink() {
	pactl list sinks short 2>/dev/null | awk -v re="$sink_regex" '$2 ~ re { print $2; exit }'
}

detect_alsa_card() {
	local src="$1" num c
	if [[ -n "$alsa_card" ]]; then
		echo "$alsa_card"
		return 0
	fi
	num="$(pactl list sources 2>/dev/null | awk -v name="$src" '
		$1 == "Name:" && $2 == name { show = 1 }
		show && $1 == "alsa.card" && $2 == "=" { print $3; exit }
	')"
	if [[ -n "${num:-}" ]]; then
		echo "$num"
		return 0
	fi
	for c in /proc/asound/card[0-9]*; do
		[[ -d "$c" ]] || continue
		if grep -qi 'alc897' "$c"/codec#* 2>/dev/null; then
			basename "$c" | tr -cd '0-9'
			return 0
		fi
	done
	if [[ -f /proc/asound/cards ]]; then
		awk '/HD-Audio Generic|ALC897|Ryzen HD Audio/ { print $1; exit }' /proc/asound/cards
	fi
}

fix_alsa_loopback() {
	local card="$1"
	command -v amixer >/dev/null 2>&1 || return 0

	amixer -c "$card" sset 'Front Mic' 0% off 2>/dev/null || true
	amixer -c "$card" sset 'Rear Mic' 0% off 2>/dev/null || true
	amixer -c "$card" sset 'Line' 0% off 2>/dev/null || true
	amixer -c "$card" set 'Loopback Mixing' 'Disabled' 2>/dev/null || true
	amixer -c "$card" set 'Input Source',0 'Front Mic' 2>/dev/null || true
	amixer -c "$card" set 'Input Source',1 'Front Mic' 2>/dev/null || true
	amixer -c "$card" sset 'Capture',1 off 2>/dev/null || true
	amixer -c "$card" sset 'Front Mic Boost' 0% 2>/dev/null || true
}

unload_echo_modules() {
	local mid
	while read -r mid; do
		[[ -n "$mid" ]] || continue
		pactl unload-module "$mid" 2>/dev/null || true
	done < <(pactl list modules short 2>/dev/null | awk '/module-echo-cancel/{print $1}')
}

load_echo_cancel() {
	local src="$1" sink="$2"
	local -a extra=()
	unload_echo_modules
	if [[ -n "${AUDIO_ECHO_CANCEL_EXTRA_ARGS:-}" ]]; then
		# shellcheck disable=SC2206
		extra=( $AUDIO_ECHO_CANCEL_EXTRA_ARGS )
	fi
	pactl load-module module-echo-cancel \
		aec_method=webrtc \
		"${extra[@]}" \
		source_name="$echo_source" \
		sink_name="$echo_sink" \
		source_master="$src" \
		sink_master="$sink" >/dev/null
}

wait_for_devices() {
	local i src="" sink=""
	for i in $(seq 1 40); do
		src="$(find_analog_source || true)"
		sink="$(find_analog_sink || true)"
		[[ -n "$src" && -n "$sink" ]] && break
		sleep 0.25
	done
	echo "$src"
	echo "$sink"
}

move_analog_playback_to_echo_sink() {
	local master_sink="$1"
	local master_idx input_idx
	master_idx="$(pactl list sinks short 2>/dev/null | awk -v n="$master_sink" '$2 == n { print $1; exit }')"
	[[ -n "${master_idx:-}" ]] || return 0
	while read -r input_idx _sink_idx _rest; do
		[[ -n "${input_idx:-}" ]] || continue
		[[ "$_sink_idx" == "$master_idx" ]] || continue
		pactl move-sink-input "$input_idx" "$echo_sink" 2>/dev/null || true
	done < <(pactl list sink-inputs short 2>/dev/null)
}

move_analog_capture_to_echo_source() {
	local master_source="$1"
	local master_idx output_idx
	master_idx="$(pactl list sources short 2>/dev/null | awk -v n="$master_source" '$2 == n { print $1; exit }')"
	[[ -n "${master_idx:-}" ]] || return 0
	while read -r output_idx _src_idx _rest; do
		[[ -n "${output_idx:-}" ]] || continue
		[[ "$_src_idx" == "$master_idx" ]] || continue
		pactl move-source-output "$output_idx" "$echo_source" 2>/dev/null || true
	done < <(pactl list source-outputs short 2>/dev/null)
}

main() {
	local -a devs=()
	local src sink card changed=0
	mapfile -t devs < <(wait_for_devices)
	src="${devs[0]:-}"
	sink="${devs[1]:-}"

	if [[ -z "${src:-}" || -z "${sink:-}" ]]; then
		toast_warn "Mic setup: onboard analog source/sink not found."
		exit 1
	fi

	card="$(detect_alsa_card "$src" || true)"
	if [[ -n "${card:-}" ]]; then
		fix_alsa_loopback "$card"
	fi

	if ! pactl list sources short 2>/dev/null | awk -v n="$echo_source" '$2 == n { found=1 } END { exit !found }'; then
		load_echo_cancel "$src" "$sink"
		changed=1
	fi

	if pactl set-default-source "$echo_source" 2>/dev/null; then
		changed=1
	fi
	if pactl set-default-sink "$echo_sink" 2>/dev/null; then
		changed=1
	fi

	move_analog_playback_to_echo_sink "$sink"
	move_analog_capture_to_echo_source "$src"

	if [[ "$changed" -eq 1 ]]; then
		toast_info "Audio: echo-cancel on mic + speakers (fixes desktop bleed)"
	fi
}

main "$@"
