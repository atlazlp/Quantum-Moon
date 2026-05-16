pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services

Scope {
    LazyLoader {
        id: loader

        active: QuantumMoon.active

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "quantum-moon-fade"
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                color: "transparent"

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                mask: Region {}

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: QuantumMoon.overlayOpacity
                }
            }
        }
    }
}
