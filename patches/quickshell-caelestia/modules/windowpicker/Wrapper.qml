pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.windowpicker.items
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property var panels

    property var pendingKill: null
    property bool pointerInside: root.shouldBeActive && pickerHover.hovered

    readonly property bool killConfirmOpen: pendingKill !== null && pendingKill !== undefined

    readonly property bool launcherUiVisible: (visibilities.launcher && Config.launcher.enabled) || panels.launcher.offsetScale < 1.0
    readonly property bool shouldBeActive: visibilities.windowPicker && !launcherUiVisible && !LauncherItemOverrides.launcherJustUsed()

    function requestKill(row: var): void {
        pendingKill = row;
    }

    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 - Tokens.spacing.large;
        if (visibilities.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            visibilities.launcher = false;
            implicitHeight = Qt.binding(() => content.implicitHeight);
            implicitWidth = Qt.binding(() => content.implicitWidth || 630);
        } else {
            implicitHeight = implicitHeight;
            implicitWidth = implicitWidth;
            pendingKill = null;
        }
    }

    visible: offsetScale < 1
    enabled: root.shouldBeActive || (panels.launcher.offsetScale ?? 0) >= 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale

    HoverHandler {
        id: pickerHover

        enabled: root.shouldBeActive
    }

    Behavior on offsetScale {
        enabled: !root.launcherUiVisible
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            visibilities: root.visibilities
            panels: root.panels
            maxHeight: root.maxHeight
            onKillRequest: row => root.requestKill(row)
        }
    }

    onPendingKillChanged: {
        if (root.pendingKill !== null && root.pendingKill !== undefined) {
            Qt.callLater(() => {
                content.item?.releaseKillDialogInput?.();
                Qt.callLater(() => killConfirmOverlay.forceActiveFocus());
            });
        }
    }

    KillConfirmOverlay {
        id: killConfirmOverlay

        parent: root.panels.parent
        anchors.fill: parent
        z: 1_000_000
        visibilities: root.visibilities
        target: root.pendingKill

        onDismissed: root.pendingKill = null
    }
}
