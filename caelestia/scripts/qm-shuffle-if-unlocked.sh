#!/usr/bin/env bash
set -eu

state="${HOME}/.local/state/quantum-moon/state.json"
if [[ -f "${state}" ]] && command -v jq >/dev/null 2>&1; then
	if jq -e '.planetLocked == true' "${state}" >/dev/null 2>&1; then
		exit 0
	fi
fi

root_file="${HOME}/.config/caelestia/quantum-moon-root"
[[ -f "${root_file}" ]] || exit 0
QM=""
read -r QM <"${root_file}" || exit 0
[[ -n "${QM}" && -x "${QM}/scripts/qm-random" ]] || exit 0
exec "${QM}/scripts/qm-random"
