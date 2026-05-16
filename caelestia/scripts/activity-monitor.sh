#!/usr/bin/env bash
set -euo pipefail
if command -v mission-center >/dev/null 2>&1; then exec mission-center; fi
if command -v gnome-system-monitor >/dev/null 2>&1; then exec gnome-system-monitor; fi
if command -v kitty >/dev/null 2>&1; then exec kitty --class activitymon --title Activity -e btop; fi
if command -v foot >/dev/null 2>&1; then exec foot -a activitymon --title Activity -e btop; fi
exec btop
