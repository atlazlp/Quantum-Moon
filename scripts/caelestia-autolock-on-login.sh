#!/usr/bin/env sh
# exec-once: lock session right after qs answers IPC (pairs with SDDM Autologin).
set -eu
QS=$(command -v qs) || exit 1
if [ "${CAELESTIA_SKIP_BOOT_LOCK:-}" = 1 ]; then
	exit 0
fi
t=0
while [ "$t" -lt 150 ]; do
	if "$QS" -c caelestia ipc call lock lock >/dev/null 2>&1; then
		exit 0
	fi
	t=$((t + 1))
	sleep 0.1
done
exit 1
