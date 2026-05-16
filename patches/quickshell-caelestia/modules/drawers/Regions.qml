pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.modules.bar as Bar

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    property bool shellReceivesLauncherPointer: false
    property bool shellReceivesWindowPickerPointer: false

    readonly property bool immersivePointer: shellReceivesLauncherPointer || shellReceivesWindowPickerPointer

    readonly property real borderThickness: win.contentItem.Config.border.thickness
    readonly property real clampedThickness: win.contentItem.Config.border.clampedThickness

    x: immersivePointer ? win.dragMaskPadding : (bar.clampedWidth + win.dragMaskPadding)
    y: clampedThickness + win.dragMaskPadding
    width: win.width - (immersivePointer ? (win.dragMaskPadding * 2 + clampedThickness) : (bar.clampedWidth + win.dragMaskPadding * 2 + clampedThickness))
    height: win.height - clampedThickness * 2 - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    readonly property real launcherCutoutH: shellReceivesLauncherPointer ? 0 : (root.panels.launcher.height * (1 - root.panels.launcher.offsetScale) + root.borderThickness)
    readonly property real pickerCutoutH: shellReceivesWindowPickerPointer ? 0 : (root.panels.windowPicker.height * (1 - root.panels.windowPicker.offsetScale) + root.borderThickness)
    readonly property real utilitiesCutoutH: immersivePointer ? 0 : (root.panels.utilities.height * (1 - root.panels.utilities.offsetScale) + root.borderThickness)

    R {
        panel: root.panels.dashboard
        y: 0
        height: panel.height * (1 - root.panels.dashboard.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.quantumMoonPanel
        y: 0
        height: panel.height * (1 - root.panels.quantumMoonPanel.offsetScale) + root.borderThickness
    }

    Region {
        x: root.panels.launcher.x + root.bar.implicitWidth
        y: root.win.height - root.launcherCutoutH
        width: shellReceivesLauncherPointer ? 0 : root.panels.launcher.width
        height: root.launcherCutoutH
        intersection: Intersection.Subtract
    }

    Region {
        x: root.panels.windowPicker.x + root.bar.implicitWidth
        y: root.win.height - root.pickerCutoutH
        width: shellReceivesWindowPickerPointer ? 0 : root.panels.windowPicker.width
        height: root.pickerCutoutH
        intersection: Intersection.Subtract
    }

    R {
        id: sessionRegion

        panel: root.panels.sessionWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.session.offsetScale) + root.borderThickness + sidebarRegion.width
    }

    R {
        id: sidebarRegion

        panel: root.panels.sidebar
        x: root.win.width - width
        width: panel.width * (1 - root.panels.sidebar.offsetScale) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        width: panel.width * (1 - root.panels.osd.offsetScale) + root.borderThickness + sessionRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: panel.height + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        y: root.win.height - root.utilitiesCutoutH
        width: immersivePointer ? 0 : panel.width
        height: root.utilitiesCutoutH
    }

    R {
        panel: root.panels.popoutsWrapper
        width: immersivePointer ? 0 : (panel.width * (1 - root.panels.popoutsWrapper.offsetScale))
    }

    component R: Region {
        required property Item panel

        x: panel.x + root.bar.implicitWidth
        y: panel.y + root.borderThickness
        width: panel.width
        height: panel.height
        intersection: Intersection.Subtract
    }
}
