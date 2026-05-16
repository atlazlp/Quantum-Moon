#!/usr/bin/env bash
set -euo pipefail

# Toggle PipeWire sink port on onboard ALC897-style codec (rear line-out vs front headphone jack).

card_id="${AUDIO_ANALOG_CARD:-alsa_card.pci-0000_11_00.6}"
sink_name="${AUDIO_ANALOG_SINK:-alsa_output.pci-0000_11_00.6.analog-stereo}"
port_speakers="analog-output-lineout"
port_headphones="analog-output-headphones"
state_file="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/audio-analog-port"

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

if ! command -v pactl >/dev/null 2>&1; then
	toast_warn "pactl not installed — analog toggle skipped."
	exit 0
fi

if ! pactl list cards short 2>/dev/null | awk '{print $2}' | grep -qxF "$card_id"; then
	card_id="$(pactl list cards short 2>/dev/null | awk '$0 ~ /11_00\.6/ {print $2; exit}')"
fi
if [[ -z "${card_id:-}" ]]; then
	toast_warn "Analog toggle: no matching onboard card (set AUDIO_ANALOG_CARD if needed)."
	exit 0
fi

if ! pactl list sinks short 2>/dev/null | awk '{print $2}' | grep -qxF "$sink_name"; then
	sink_name="$(pactl list sinks short 2>/dev/null | awk '/11_00\.6\.analog-stereo/ {print $2; exit}')"
fi
if [[ -z "${sink_name:-}" ]]; then
	toast_warn "Analog toggle: stereo sink not found — skipped."
	exit 0
fi

active="$(pactl list sinks 2>/dev/null | awk -v sink="$sink_name" '
	$1 == "Name:" && $2 == sink { show=1 }
	show && $1 == "Active" && $2 == "Port:" { print $3; exit }
')"

case "$active" in
	"$port_headphones") next="$port_speakers" ; label="Speakers (line out)" ;;
	"$port_speakers") next="$port_headphones" ; label="Headphones (front)" ;;
	*)
		if [[ -f "$state_file" ]] && grep -q "$port_headphones" "$state_file" 2>/dev/null; then
			next="$port_speakers"
			label="Speakers (line out)"
		else
			next="$port_headphones"
			label="Headphones (front)"
		fi
		;;
esac

pactl set-sink-port "$sink_name" "$next"
mkdir -p "$(dirname "$state_file")"
printf '%s\n' "$next" >"$state_file"

toast_info "Output: ${label}"
