#!/usr/bin/env bash
set -euo pipefail

HOME="${HOME:?}"
GTK3_MARKS="${HOME}/.config/gtk-3.0/bookmarks"
GTK4_MARKS="${HOME}/.config/gtk-4.0/bookmarks"
GTK4_CSS="${HOME}/.config/gtk-4.0/gtk.css"
CSS_BEGIN="/* BEGIN caelestia-nautilus-sidebar */"
CSS_END="/* END caelestia-nautilus-sidebar */"

file_uri() {
	python3 -c '
from pathlib import Path
from urllib.parse import quote
import sys
p = Path(sys.argv[1]).expanduser()
try:
    p = p.resolve()
except OSError:
    p = Path(sys.argv[1]).expanduser()
print("file://" + quote(str(p), safe="/"))
' "$1"
}

bookmark_line() {
	local dir="$1" label="$2"
	mkdir -p "${dir}"
	printf '%s %s\n' "$(file_uri "${dir}")" "${label}"
}

load_xdg_dirs() {
	if [[ -f "${HOME}/.config/user-dirs.dirs" ]]; then
		set -a
		# shellcheck disable=SC1091
		. "${HOME}/.config/user-dirs.dirs"
		set +a
	fi
}

extra_mounts_count() {
	local f="${HOME}/.config/caelestia/nautilus-sidebar-extra"
	local n=0 line path rest
	[[ -f "${f}" ]] || {
		printf '%s' "0"
		return 0
	}
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
		read -r path rest <<<"${line}"
		[[ -z "${path}" ]] && continue
		[[ "${path}" =~ ^/ ]] || continue
		[[ -d "${path}" ]] || continue
		n=$((n + 1))
	done <"${f}"
	printf '%s' "${n}"
}

apply_drive_icons() {
	local f="${HOME}/.config/caelestia/nautilus-drive-icons"
	local line path icon rest
	[[ -f "${f}" ]] || return 0
	command -v gio >/dev/null 2>&1 || return 0
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
		read -r path icon rest <<<"${line}"
		[[ -z "${path}" || -z "${icon}" ]] && continue
		[[ "${path}" =~ ^/ ]] || continue
		[[ -d "${path}" ]] || continue
		gio set -t string "${path}" metadata::custom-icon-name "${icon}" 2>/dev/null || true
	done <"${f}"
}

rewrite_gtk4_mount_splitter_css() {
	local n_mounts="$1"
	mkdir -p "$(dirname "${GTK4_CSS}")"
	touch "${GTK4_CSS}"
	local tail="${NAUTILUS_SIDEBAR_TAIL_ROWS:-1}"
	if [[ ! "${tail}" =~ ^[0-9]+$ ]]; then
		tail=1
	fi
	local nth=$((n_mounts + tail))
	export NAUTILUS_SPLIT_NTH="${nth}"
	export NAUTILUS_MOUNT_COUNT="${n_mounts}"
	export GTK4_CSS_PATH="${GTK4_CSS}"
	export CSS_BEGIN CSS_END
	python3 - <<'PY'
import os, re
path = os.environ["GTK4_CSS_PATH"]
begin = os.environ["CSS_BEGIN"]
end = os.environ["CSS_END"]
n_mounts = int(os.environ["NAUTILUS_MOUNT_COUNT"])
nth = int(os.environ["NAUTILUS_SPLIT_NTH"])
with open(path, encoding="utf-8") as f:
    text = f.read()
pat = re.escape(begin) + r".*?" + re.escape(end) + r"\s*"
text = re.sub(pat, "", text, flags=re.S)
if n_mounts > 0:
    sel = (
        f".nautilus-window placessidebar list.navigation-sidebar row:nth-last-child({nth}),\n"
        f".nautilus-window placessidebar listview.navigation-sidebar row:nth-last-child({nth}),\n"
        f".nautilus-window placessidebar row.sidebar-row:nth-last-child({nth}),\n"
        f"window.org-gnome-Nautilus placessidebar list.navigation-sidebar row:nth-last-child({nth})"
    )
    block = (
        f"{begin}\n"
        "/* Border-top on first pinned-mount row (below XDG bookmarks, above mount block). */\n"
        "/* nth-last-child(mounts + tail): tail = rows below last mount (often 1). */\n"
        f"{sel} {{\n"
        "  border-top: 1px solid color-mix(in srgb, currentColor 17%, transparent) !important;\n"
        "  margin-top: 10px !important;\n"
        "  padding-top: 8px !important;\n"
        "}\n"
        f"{end}\n"
    )
    text = text.rstrip() + "\n\n" + block + "\n"
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
PY
}

apply_nautilus_prefs() {
	command -v gsettings >/dev/null 2>&1 || return 0
	gsettings list-schemas 2>/dev/null | grep -qxF org.gnome.nautilus.preferences || return 0
	gsettings set org.gnome.nautilus.preferences sort-directories-first true 2>/dev/null || true
	gsettings set org.gnome.nautilus.preferences default-sort-order "name" 2>/dev/null || true
	if gsettings list-keys org.gnome.nautilus.preferences 2>/dev/null | grep -qxF show-delete-permanently; then
		gsettings set org.gnome.nautilus.preferences show-delete-permanently false 2>/dev/null || true
	fi

	if [[ "${NAUTILUS_DISABLE_SYSTEM_RECENT:-}" == "1" ]]; then
		if gsettings list-schemas 2>/dev/null | grep -qxF org.gnome.desktop.privacy; then
			if gsettings list-keys org.gnome.desktop.privacy 2>/dev/null | grep -qxF remember-recent-files; then
				gsettings set org.gnome.desktop.privacy remember-recent-files false 2>/dev/null || true
			fi
		fi
	else
		if gsettings list-schemas 2>/dev/null | grep -qxF org.gnome.desktop.privacy; then
			if gsettings list-keys org.gnome.desktop.privacy 2>/dev/null | grep -qxF remember-recent-files; then
				gsettings set org.gnome.desktop.privacy remember-recent-files true 2>/dev/null || true
			fi
		fi
	fi
}

append_extra_from_config() {
	local f="${HOME}/.config/caelestia/nautilus-sidebar-extra"
	local line path rest label
	[[ -f "${f}" ]] || return 0
	while IFS= read -r line || [[ -n "${line}" ]]; do
		[[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
		read -r path rest <<<"${line}"
		[[ -z "${path}" ]] && continue
		[[ "${path}" =~ ^/ ]] || continue
		[[ -d "${path}" ]] || continue
		if [[ -n "${rest}" ]]; then
			label="${rest}"
		else
			label="$(basename "${path}")"
		fi
		bookmark_line "${path}" "${label}"
	done <"${f}"
}

build_bookmarks() {
	load_xdg_dirs
	local docs downloads desktop pictures music videos publicshare templates
	docs="${XDG_DOCUMENTS_DIR:-${HOME}/Documents}"
	downloads="${XDG_DOWNLOAD_DIR:-${HOME}/Downloads}"
	desktop="${XDG_DESKTOP_DIR:-${HOME}/Desktop}"
	pictures="${XDG_PICTURES_DIR:-${HOME}/Pictures}"
	music="${XDG_MUSIC_DIR:-${HOME}/Music}"
	videos="${XDG_VIDEOS_DIR:-${HOME}/Videos}"
	publicshare="${XDG_PUBLICSHARE_DIR:-${HOME}/Public}"
	templates="${XDG_TEMPLATES_DIR:-${HOME}/Templates}"

	{
		bookmark_line "${docs}" "Documents"
		bookmark_line "${downloads}" "Downloads"
		bookmark_line "${desktop}" "Desktop"
		bookmark_line "${pictures}" "Pictures"
		bookmark_line "${music}" "Music"
		bookmark_line "${videos}" "Videos"
		bookmark_line "${HOME}/Projects" "Projects"
		bookmark_line "${publicshare}" "Public"
		bookmark_line "${templates}" "Templates"
		append_extra_from_config
	}
}

merge_bookmarks() {
	local line uri tmp body home_uri
	mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
	home_uri="$(file_uri "${HOME}")"
	body="$(build_bookmarks)"
	tmp="$(mktemp)"
	printf '%s\n' "${body}" >"${tmp}"
	if [[ -f "${GTK3_MARKS}" ]]; then
		while IFS= read -r line || [[ -n "${line}" ]]; do
			[[ -z "${line}" ]] && continue
			uri="${line%% *}"
			case "${line}" in
			trash:///*|"${home_uri}"*) continue ;;
			esac
			grep -qF "${uri} " "${tmp}" 2>/dev/null && continue
			printf '%s\n' "${line}" >>"${tmp}"
		done <"${GTK3_MARKS}"
	fi
	mv "${tmp}" "${GTK3_MARKS}"
	cp -f "${GTK3_MARKS}" "${GTK4_MARKS}"
}

main() {
	mkdir -p "${HOME}/.config/gtk-3.0" "${HOME}/.config/gtk-4.0"
	if [[ "${NAUTILUS_BOOKMARKS_FORCE:-}" == "1" ]]; then
		build_bookmarks >"${GTK3_MARKS}"
		cp -f "${GTK3_MARKS}" "${GTK4_MARKS}"
		echo "Wrote GTK bookmarks (${GTK3_MARKS}); pinned mounts last after XDG rows. Unknown URIs from the old file were appended. NAUTILUS_BOOKMARKS_FORCE=1 drops those extras."
	else
		merge_bookmarks
		echo "Synced GTK bookmarks (${GTK3_MARKS}): template order + preserved extra URIs not in template. NAUTILUS_BOOKMARKS_FORCE=1 replaces with template only."
	fi

	local n_mounts tail nth
	n_mounts="$(extra_mounts_count)"
	tail="${NAUTILUS_SIDEBAR_TAIL_ROWS:-1}"
	[[ "${tail}" =~ ^[0-9]+$ ]] || tail=1
	nth=$((n_mounts + tail))
	rewrite_gtk4_mount_splitter_css "${n_mounts}"
	apply_drive_icons
	apply_nautilus_prefs

	echo "Nautilus: splitter border-top on sidebar row nth-last-child(${nth}) (= ${n_mounts} mount(s) + tail ${tail}); set NAUTILUS_SIDEBAR_TAIL_ROWS=0 if nothing sits below mounts. Drive icons: ~/.config/caelestia/nautilus-drive-icons. Recent on unless NAUTILUS_DISABLE_SYSTEM_RECENT=1."
}

main "$@"
