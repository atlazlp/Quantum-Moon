#!/usr/bin/env bash
set -eu

resume_displays() {
	sleep 0.75
	command -v hyprctl >/dev/null 2>&1 || return 0
	hyprctl dispatch dpms on 2>/dev/null || true
	if command -v jq >/dev/null 2>&1; then
		hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r mon; do
			[[ -n "${mon}" ]] || continue
			hyprctl dispatch dpms on "${mon}" 2>/dev/null || true
		done
	fi
}

shuffle_quantum_moon_before_sleep() {
	local shuffle="${HOME}/.config/caelestia/scripts/qm-shuffle-if-unlocked.sh"
	[[ -x "${shuffle}" ]] || return
	"${shuffle}"
}

command -v dbus-monitor >/dev/null 2>&1 || exit 0

dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
	while read -r line; do
		case "${line}" in
		*boolean\ true*)
			shuffle_quantum_moon_before_sleep
			;;
		*boolean\ false*)
			resume_displays
			;;
		esac
	done
