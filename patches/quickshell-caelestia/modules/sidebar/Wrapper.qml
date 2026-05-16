pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    Config.screen: root.screen.name
    readonly property Props props: Props {}

    readonly property bool outputAllowsSidebar: Config.sidebar.enabled
    readonly property bool shouldBeActive: visibilities.sidebar && outputAllowsSidebar

    property real offsetScale: shouldBeActive ? 0 : 1

    visible: offsetScale < 1
    anchors.rightMargin: (-implicitWidth - 5) * offsetScale
    implicitWidth: Math.round(Tokens.sizes.sidebar.width * LayoutTweaks.rightStripWidthScale)
    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large
        anchors.bottomMargin: 0

        active: root.shouldBeActive || root.visible

        sourceComponent: Content {
            implicitWidth: Math.round(Tokens.sizes.sidebar.width * LayoutTweaks.rightStripWidthScale) - Tokens.padding.large * 2
            props: root.props
            visibilities: root.visibilities
        }
    }
}
