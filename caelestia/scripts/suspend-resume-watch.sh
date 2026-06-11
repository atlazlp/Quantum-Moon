#!/usr/bin/env bash
set -eu

LOCKED_SLEEP="${HOME}/.config/caelestia/scripts/locked-sleep-after.sh"

dpms_on_all() {
	hyprctl dispatch dpms on 2>/dev/null || true
	if command -v jq >/dev/null 2>&1; then
		hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r mon; do
			[[ -n "${mon}" ]] || continue
			hyprctl dispatch dpms on "${mon}" 2>/dev/null || true
		done
	fi
}

resume_displays() {
	command -v hyprctl >/dev/null 2>&1 || return 0
	local step
	for step in 0.75 0.75 1 2.5; do
		sleep "${step}"
		dpms_on_all
	done
}

rebind_usb_hid() {
	command -v usbreset >/dev/null 2>&1 || return 0
	local devpath bus dev node
	for devpath in /sys/bus/usb/devices/*-*; do
		[[ -d "${devpath}" ]] || continue
		name="$(basename "${devpath}")"
		[[ "${name}" =~ ^[0-9]+-[0-9]+$ ]] || continue
		for iface in "${devpath}"/*:*; do
			[[ -f "${iface}/bInterfaceClass" ]] || continue
			[[ "$(<"${iface}/bInterfaceClass")" == "03" ]] || continue
			[[ -f "${devpath}/busnum" && -f "${devpath}/devnum" ]] || continue
			bus="$(<"${devpath}/busnum")"
			dev="$(<"${devpath}/devnum")"
			node="/dev/bus/usb/$(printf '%03d' "${bus}")/$(printf '%03d' "${dev}")"
			[[ -e "${node}" ]] || continue
			usbreset "${node}" 2>/dev/null || true
			break
		done
	done
}

shuffle_quantum_moon_before_sleep() {
	local shuffle="${HOME}/.config/caelestia/scripts/qm-shuffle-if-unlocked.sh"
	[[ -x "${shuffle}" ]] || return
	"${shuffle}"
}

on_sleep() {
	[[ -x "${LOCKED_SLEEP}" ]] && bash "${LOCKED_SLEEP}" on-suspend
	shuffle_quantum_moon_before_sleep
}

on_wake() {
	[[ -x "${LOCKED_SLEEP}" ]] && bash "${LOCKED_SLEEP}" on-resume
	rebind_usb_hid
	resume_displays &
}

command -v dbus-monitor >/dev/null 2>&1 || exit 0

dbus-monitor --system "type='signal',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
	while read -r line; do
		case "${line}" in
		*boolean\ true*) on_sleep ;;
		*boolean\ false*) on_wake ;;
		esac
	done
