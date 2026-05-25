#!/usr/bin/env bash
set -euo pipefail
# Use ~/.config/quickshell/caelestia so `qs -c caelestia` prefers it over /etc/xdg.
# Per-monitor shell.json (GlobalConfig.forScreen) controls where the sidebar and lock UI appear. Re-run after major caelestia-shell upgrades.
# After editing files under patches/quickshell-caelestia/, run scripts/rebuild-caelestia-quickshell.sh to copy + restart (or this script alone if you will restart yourself).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC=/etc/xdg/quickshell/caelestia
DST="${HOME}/.config/quickshell/caelestia"
PATCH="${ROOT}/patches/quickshell-caelestia"

if [[ ! -d "$SRC" ]]; then
  echo "Missing $SRC (install caelestia-shell)" >&2
  exit 1
fi

need=( \
  "$PATCH/modules/Shortcuts.qml" \
  "$PATCH/modules/IdleMonitors.qml" \
  "$PATCH/utils/LayoutTweaks.qml" \
  "$PATCH/services/Screens.qml" \
  "$PATCH/services/Visibilities.qml" \
  "$PATCH/services/QuantumMoon.qml" \
  "$PATCH/services/LauncherItemOverrides.qml" \
  "$PATCH/services/ProtonGhosts.qml" \
  "$PATCH/services/NotifFocus.qml" \
  "$PATCH/services/BarVpn.qml" \
  "$PATCH/services/Hypr.qml" \
  "$PATCH/services/NotifData.qml" \
  "$PATCH/components/DrawerVisibilities.qml" \
  "$PATCH/components/LauncherItemEditOverlay.qml" \
  "$PATCH/modules/background/Background.qml" \
  "$PATCH/modules/background/Visualiser.qml" \
  "$PATCH/modules/bar/Bar.qml" \
  "$PATCH/modules/bar/BarWrapper.qml" \
  "$PATCH/modules/bar/components/ActiveWindow.qml" \
  "$PATCH/modules/bar/components/OsIcon.qml" \
  "$PATCH/modules/bar/components/Tray.qml" \
  "$PATCH/modules/bar/components/Clock.qml" \
  "$PATCH/modules/bar/components/StatusIcons.qml" \
  "$PATCH/modules/bar/popouts/Audio.qml" \
  "$PATCH/services/Audio.qml" \
  "$PATCH/modules/bar/components/workspaces/Workspaces.qml" \
  "$PATCH/modules/bar/components/workspaces/Workspace.qml" \
  "$PATCH/modules/bar/components/workspaces/ActiveIndicator.qml" \
  "$PATCH/modules/bar/components/workspaces/OccupiedBg.qml" \
  "$PATCH/modules/notifications/Content.qml" \
  "$PATCH/modules/notifications/Notification.qml" \
  "$PATCH/modules/launcher/Wrapper.qml" \
  "$PATCH/modules/launcher/Content.qml" \
  "$PATCH/modules/launcher/items/AppItem.qml" \
  "$PATCH/modules/sidebar/Wrapper.qml" \
  "$PATCH/modules/sidebar/NotifActionList.qml" \
  "$PATCH/modules/sidebar/NotifGroupList.qml" \
  "$PATCH/modules/utilities/Wrapper.qml" \
  "$PATCH/modules/lock/Lock.qml" \
  "$PATCH/modules/lock/LockSurface.qml" \
  "$PATCH/modules/lock/Fetch.qml" \
  "$PATCH/modules/dashboard/dash/User.qml" \
  "$PATCH/modules/drawers/Exclusions.qml" \
  "$PATCH/modules/drawers/Panels.qml" \
  "$PATCH/modules/drawers/ContentWindow.qml" \
  "$PATCH/modules/drawers/Interactions.qml" \
  "$PATCH/modules/drawers/QuantumMoonPanel.qml" \
  "$PATCH/modules/drawers/QuantumMoonOverlay.qml" \
  "$PATCH/modules/drawers/Regions.qml" \
  "$PATCH/modules/windowpicker/Wrapper.qml" \
  "$PATCH/modules/windowpicker/Content.qml" \
  "$PATCH/modules/windowpicker/WindowList.qml" \
  "$PATCH/modules/windowpicker/items/WindowRow.qml" \
  "$PATCH/modules/windowpicker/items/KillConfirmOverlay.qml" \
  "$PATCH/shell.qml" \
)
for f in "${need[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "Missing patch file: $f" >&2
    exit 1
  fi
done

if [[ ! -f "$DST/shell.qml" ]]; then
  echo "Copying Caelestia shell to $DST (one-time; ~duplicate of package tree)."
  mkdir -p "$(dirname "$DST")"
  cp -a "$SRC" "$DST"
fi

install -m644 "$PATCH/utils/LayoutTweaks.qml" "$DST/utils/LayoutTweaks.qml"
install -m644 "$PATCH/services/Screens.qml" "$DST/services/Screens.qml"
install -m644 "$PATCH/services/Visibilities.qml" "$DST/services/Visibilities.qml"
install -m644 "$PATCH/services/QuantumMoon.qml" "$DST/services/QuantumMoon.qml"
install -m644 "$PATCH/services/LauncherItemOverrides.qml" "$DST/services/LauncherItemOverrides.qml"
install -m644 "$PATCH/services/ProtonGhosts.qml" "$DST/services/ProtonGhosts.qml"
install -m644 "$PATCH/services/NotifFocus.qml" "$DST/services/NotifFocus.qml"
install -m644 "$PATCH/services/BarVpn.qml" "$DST/services/BarVpn.qml"
install -m644 "$PATCH/services/Hypr.qml" "$DST/services/Hypr.qml"
install -m644 "$PATCH/services/NotifData.qml" "$DST/services/NotifData.qml"
rm -f "$DST/services/CmxVpn.qml" "$DST/caelestia/services/CmxVpn.qml"
install -m644 "$PATCH/services/Audio.qml" "$DST/services/Audio.qml"
install -m644 "$PATCH/shell.qml" "$DST/shell.qml"
mkdir -p "$DST/components"
install -m644 "$PATCH/components/DrawerVisibilities.qml" "$DST/components/DrawerVisibilities.qml"
install -m644 "$PATCH/components/LauncherItemEditOverlay.qml" "$DST/components/LauncherItemEditOverlay.qml"
mkdir -p "$DST/modules"
install -m644 "$PATCH/modules/Shortcuts.qml" "$DST/modules/Shortcuts.qml"
install -m644 "$PATCH/modules/IdleMonitors.qml" "$DST/modules/IdleMonitors.qml"
mkdir -p "$DST/modules/background"
install -m644 "$PATCH/modules/background/Background.qml" "$DST/modules/background/Background.qml"
install -m644 "$PATCH/modules/background/Visualiser.qml" "$DST/modules/background/Visualiser.qml"
mkdir -p "$DST/modules/bar/components/workspaces"
install -m644 "$PATCH/modules/bar/Bar.qml" "$DST/modules/bar/Bar.qml"
install -m644 "$PATCH/modules/bar/BarWrapper.qml" "$DST/modules/bar/BarWrapper.qml"
rm -f "$DST/modules/bar/components/QuantumMoon.qml"
install -m644 "$PATCH/modules/bar/components/ActiveWindow.qml" "$DST/modules/bar/components/ActiveWindow.qml"
install -m644 "$PATCH/modules/bar/components/OsIcon.qml" "$DST/modules/bar/components/OsIcon.qml"
install -m644 "$PATCH/modules/bar/components/Tray.qml" "$DST/modules/bar/components/Tray.qml"
install -m644 "$PATCH/modules/bar/components/Clock.qml" "$DST/modules/bar/components/Clock.qml"
install -m644 "$PATCH/modules/bar/components/StatusIcons.qml" "$DST/modules/bar/components/StatusIcons.qml"
mkdir -p "$DST/modules/bar/popouts"
install -m644 "$PATCH/modules/bar/popouts/Audio.qml" "$DST/modules/bar/popouts/Audio.qml"
install -m644 "$PATCH/modules/bar/components/workspaces/Workspaces.qml" "$DST/modules/bar/components/workspaces/Workspaces.qml"
install -m644 "$PATCH/modules/bar/components/workspaces/Workspace.qml" "$DST/modules/bar/components/workspaces/Workspace.qml"
rm -f "$DST/modules/bar/components/workspaces/SpecialWorkspaces.qml" "$DST/caelestia/modules/bar/components/workspaces/SpecialWorkspaces.qml"
install -m644 "$PATCH/modules/bar/components/workspaces/ActiveIndicator.qml" "$DST/modules/bar/components/workspaces/ActiveIndicator.qml"
install -m644 "$PATCH/modules/bar/components/workspaces/OccupiedBg.qml" "$DST/modules/bar/components/workspaces/OccupiedBg.qml"
mkdir -p "$DST/modules/notifications"
install -m644 "$PATCH/modules/notifications/Content.qml" "$DST/modules/notifications/Content.qml"
install -m644 "$PATCH/modules/notifications/Notification.qml" "$DST/modules/notifications/Notification.qml"
mkdir -p "$DST/modules/launcher"
install -m644 "$PATCH/modules/launcher/Wrapper.qml" "$DST/modules/launcher/Wrapper.qml"
install -m644 "$PATCH/modules/launcher/Content.qml" "$DST/modules/launcher/Content.qml"
mkdir -p "$DST/modules/launcher/items"
install -m644 "$PATCH/modules/launcher/items/AppItem.qml" "$DST/modules/launcher/items/AppItem.qml"
install -m644 "$PATCH/modules/sidebar/Wrapper.qml" "$DST/modules/sidebar/Wrapper.qml"
install -m644 "$PATCH/modules/sidebar/NotifActionList.qml" "$DST/modules/sidebar/NotifActionList.qml"
install -m644 "$PATCH/modules/sidebar/NotifGroupList.qml" "$DST/modules/sidebar/NotifGroupList.qml"
install -m644 "$PATCH/modules/utilities/Wrapper.qml" "$DST/modules/utilities/Wrapper.qml"
install -m644 "$PATCH/modules/lock/Lock.qml" "$DST/modules/lock/Lock.qml"
install -m644 "$PATCH/modules/lock/LockSurface.qml" "$DST/modules/lock/LockSurface.qml"
install -m644 "$PATCH/modules/lock/Fetch.qml" "$DST/modules/lock/Fetch.qml"
mkdir -p "$DST/modules/dashboard/dash"
install -m644 "$PATCH/modules/dashboard/dash/User.qml" "$DST/modules/dashboard/dash/User.qml"
install -m644 "$PATCH/modules/drawers/Exclusions.qml" "$DST/modules/drawers/Exclusions.qml"
install -m644 "$PATCH/modules/drawers/Panels.qml" "$DST/modules/drawers/Panels.qml"
install -m644 "$PATCH/modules/drawers/ContentWindow.qml" "$DST/modules/drawers/ContentWindow.qml"
install -m644 "$PATCH/modules/drawers/Interactions.qml" "$DST/modules/drawers/Interactions.qml"
install -m644 "$PATCH/modules/drawers/QuantumMoonPanel.qml" "$DST/modules/drawers/QuantumMoonPanel.qml"
install -m644 "$PATCH/modules/drawers/QuantumMoonOverlay.qml" "$DST/modules/drawers/QuantumMoonOverlay.qml"
install -m644 "$PATCH/modules/drawers/Regions.qml" "$DST/modules/drawers/Regions.qml"
mkdir -p "$DST/modules/windowpicker/items"
install -m644 "$PATCH/modules/windowpicker/Wrapper.qml" "$DST/modules/windowpicker/Wrapper.qml"
install -m644 "$PATCH/modules/windowpicker/Content.qml" "$DST/modules/windowpicker/Content.qml"
install -m644 "$PATCH/modules/windowpicker/WindowList.qml" "$DST/modules/windowpicker/WindowList.qml"
install -m644 "$PATCH/modules/windowpicker/items/WindowRow.qml" "$DST/modules/windowpicker/items/WindowRow.qml"
install -m644 "$PATCH/modules/windowpicker/items/KillConfirmOverlay.qml" "$DST/modules/windowpicker/items/KillConfirmOverlay.qml"

if [[ -d "$DST/caelestia/modules" ]]; then
  install -m644 "$PATCH/modules/IdleMonitors.qml" "$DST/caelestia/modules/IdleMonitors.qml"
  install -m644 "$PATCH/services/Audio.qml" "$DST/caelestia/services/Audio.qml"
  mkdir -p "$DST/caelestia/modules/bar/popouts"
  install -m644 "$PATCH/modules/bar/popouts/Audio.qml" "$DST/caelestia/modules/bar/popouts/Audio.qml"
  mkdir -p "$DST/caelestia/modules/bar" "$DST/caelestia/modules/drawers" "$DST/caelestia/modules/background"
  install -m644 "$PATCH/modules/bar/BarWrapper.qml" "$DST/caelestia/modules/bar/BarWrapper.qml"
  install -m644 "$PATCH/modules/drawers/Exclusions.qml" "$DST/caelestia/modules/drawers/Exclusions.qml"
  install -m644 "$PATCH/modules/drawers/ContentWindow.qml" "$DST/caelestia/modules/drawers/ContentWindow.qml"
  install -m644 "$PATCH/services/Hypr.qml" "$DST/caelestia/services/Hypr.qml"
  install -m644 "$PATCH/services/NotifData.qml" "$DST/caelestia/services/NotifData.qml"
  rm -f "$DST/caelestia/modules/bar/components/workspaces/SpecialWorkspaces.qml"
  install -m644 "$PATCH/modules/drawers/Panels.qml" "$DST/caelestia/modules/drawers/Panels.qml"
  install -m644 "$PATCH/modules/drawers/Regions.qml" "$DST/caelestia/modules/drawers/Regions.qml"
  install -m644 "$PATCH/modules/background/Background.qml" "$DST/caelestia/modules/background/Background.qml"
fi

echo "Patched user shell at $DST — restart Caelestia (Ctrl+Super+Alt+R or caelestia shell -d)."
