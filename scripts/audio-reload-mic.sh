#!/usr/bin/env bash
# Re-enumerate onboard capture only (front mic jack) without restarting WirePlumber/speakers.
set -euo pipefail

card_id="${AUDIO_ANALOG_CARD:-alsa_card.pci-0000_11_00.6}"
source_name="${AUDIO_ANALOG_SOURCE:-alsa_input.pci-0000_11_00.6.analog-stereo}"
port_front="${AUDIO_ANALOG_MIC_FRONT:-analog-input-front-mic}"
port_rear="${AUDIO_ANALOG_MIC_REAR:-analog-input-rear-mic}"
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/audio-analog-mic-port"

toast_warn() {
	if command -v caelestia >/dev/null 2>&1; then
		caelestia shell toaster warn "Audio" "$1" "" 2>/dev/null || true
	else
		echo "$1" >&2
	fi
}

toast_info() {
	if command -v caelestia >/dev/null 2>&1; then
		caelestia shell toaster info "Audio" "$1" "" 2>/dev/null || true
	else
		echo "$1"
	fi
}

restart_wireplumber() {
	local u
	for u in wireplumber.service wireplumber-pulse.service; do
		if systemctl --user is-active --quiet "$u" 2>/dev/null; then
			systemctl --user restart "$u"
			return 0
		fi
	done
	return 1
}

source_has_port() {
	local src="$1" port="$2"
	pactl list sources 2>/dev/null | awk -v src="$src" -v port="$port" '
		$1 == "Name:" && $2 == src { show = 1 }
		show && $0 ~ "^[[:space:]]+" port ":" { found = 1 }
		END { exit !found }
	'
}

active_source_port() {
	local src="$1"
	pactl list sources 2>/dev/null | awk -v src="$src" '
		$1 == "Name:" && $2 == src { show = 1 }
		show && $1 == "Active" && $2 == "Port:" { print $3; exit }
	'
}

pick_fallback_port() {
	local src="$1"
	pactl list sources 2>/dev/null | awk -v src="$src" '
		$1 == "Name:" && $2 == src { show = 1 }
		show && $0 ~ /^[[:space:]]+analog-input/ {
			line = $0
			sub(/^[[:space:]]+/, "", line)
			split(line, a, ":")
			print a[1]
			exit
		}
	'
}

set_source_port() {
	pactl set-source-port "$1" "$2"
	mkdir -p "$(dirname "$state_file")"
	printf '%s\n' "$2" >"$state_file"
}

reactivate_source() {
	local src="$1"
	pactl suspend-source "$src" 1 2>/dev/null || true
	sleep 0.15
	pactl suspend-source "$src" 0 2>/dev/null || true
	pactl set-source-mute "$src" 0 2>/dev/null || true
}

if [[ "${CAELESTIA_MIC_RELOAD_FULL:-0}" == "1" ]]; then
	restart_wireplumber || true
	pactl set-source-mute @DEFAULT_SOURCE@ 0 2>/dev/null || true
	toast_info "Microphone: full PipeWire reload"
	exit 0
fi

if ! command -v pactl >/dev/null 2>&1; then
	toast_warn "pactl not installed — mic reload skipped."
	exit 1
fi

if ! pactl list cards short 2>/dev/null | awk '{print $2}' | grep -qxF "$card_id"; then
	card_id="$(pactl list cards short 2>/dev/null | awk '$0 ~ /11_00\.6/ {print $2; exit}')"
fi
if [[ -z "${card_id:-}" ]]; then
	toast_warn "Mic reload: no matching onboard card (set AUDIO_ANALOG_CARD if needed)."
	exit 1
fi

if ! pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qxF "$source_name"; then
	source_name="$(pactl list sources short 2>/dev/null | awk '/11_00\.6\.analog-stereo/ {print $2; exit}')"
fi
if [[ -z "${source_name:-}" ]]; then
	toast_warn "Mic reload: analog capture source not found — skipped."
	exit 1
fi

target="$port_front"
if ! source_has_port "$source_name" "$target"; then
	if source_has_port "$source_name" "$port_rear"; then
		target="$port_rear"
	else
		target="$(pick_fallback_port "$source_name" || true)"
	fi
fi
if [[ -z "${target:-}" ]]; then
	toast_warn "Mic reload: no analog input ports on capture source."
	exit 1
fi

active="$(active_source_port "$source_name")"
label="Front microphone"

if [[ "$active" == "$target" ]]; then
	if source_has_port "$source_name" "$port_rear" && [[ "$target" == "$port_front" ]]; then
		set_source_port "$source_name" "$port_rear"
		sleep 0.12
		set_source_port "$source_name" "$target"
		label="Front microphone (refreshed)"
	else
		reactivate_source "$source_name"
		label="Microphone (refreshed)"
	fi
else
	set_source_port "$source_name" "$target"
	if [[ "$target" == "$port_rear" ]]; then
		label="Rear microphone"
	fi
fi

reactivate_source "$source_name"

if pactl get-default-source 2>/dev/null | grep -qvF "$source_name"; then
	pactl set-default-source "$source_name" 2>/dev/null || true
fi

toast_info "Input: ${label}"
exit 0
