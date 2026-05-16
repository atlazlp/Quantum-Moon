pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.windowpicker.items

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property var panels

    property var pendingKill: null

    readonly property bool killConfirmOpen: pendingKill !== null && pendingKill !== undefined

    readonly property bool shouldBeActive: visibilities.windowPicker

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
        } else {
            implicitHeight = implicitHeight;
            pendingKill = null;
        }
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630
    opacity: 1 - offsetScale

    Behavior on offsetScale {
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
