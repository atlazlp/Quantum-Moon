pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property bool active: false

    Component.onCompleted: root.active = false

    function setActive(on: bool): void {
        if (root.active === on)
            return;
        root.active = on;
        if (on)
            root.suppressUi();
    }

    function suppressUi(): void {
        for (const [, vis] of Visibilities.screens) {
            vis.launcher = false;
            vis.windowPicker = false;
            vis.dashboard = false;
            vis.quantumMoon = false;
            vis.utilities = false;
            vis.session = false;
            vis.sidebar = false;
            vis.bar = false;
            vis.osd = false;
        }
    }

    IpcHandler {
        target: "kvm"

        function capture(on: bool): void {
            root.setActive(on);
        }
    }
}
