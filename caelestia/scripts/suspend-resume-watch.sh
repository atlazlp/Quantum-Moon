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
	local state="${HOME}/.local/state/quantum-moon/state.json"
	if [[ -f "${state}" ]] && command -v jq >/dev/null 2>&1; then
		if jq -e '.planetLocked == true' "${state}" >/dev/null 2>&1; then
			return
		fi
	fi
	local root_file="${HOME}/.config/caelestia/quantum-moon-root"
	[[ -f "${root_file}" ]] || return
	local QM=""
	read -r QM <"${root_file}" || return
	[[ -n "${QM}" && -x "${QM}/scripts/qm-random" ]] || return
	"${QM}/scripts/qm-random"
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
