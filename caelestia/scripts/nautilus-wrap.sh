#!/usr/bin/env bash
# no-css-cache: GTK otherwise keeps an old parse of ~/.config/gtk-4.0/gtk.css (theme looks “stuck”).
# Closing the last window does not quit Nautilus (background indexer); qm-apply restarts it and reopens the same folders.
# Append GNOME to XDG_CURRENT_DESKTOP so Nautilus enables GVfs volume / “Other locations” integration on Hyprland.
# To use the inspector: GTK_DEBUG=interactive,no-css-cache nautilus  then press Ctrl+Shift+I (or Ctrl+Shift+D).
bin="$(command -v nautilus)" || exit 1
[[ -n "${bin}" ]] || exit 1
desk="${XDG_CURRENT_DESKTOP:-}"
case ":${desk}:" in
*:GNOME:* | *:gnome:*) ;;
*)
	export XDG_CURRENT_DESKTOP="${desk:+$desk:}GNOME"
	;;
esac
exec env GTK_DEBUG=no-css-cache "${bin}" "$@"
