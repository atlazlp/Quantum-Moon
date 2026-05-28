pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.utils
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen

    readonly property bool disabled: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property int chromeWidth: Math.max(Config.border.minThickness, Config.border.thickness)

    readonly property int clampedWidth: Math.max(Config.border.minThickness, implicitWidth)
    readonly property int padding: Math.max(Tokens.padding.smaller, Config.border.thickness)
    readonly property int contentWidth: Math.round(Tokens.sizes.bar.innerWidth * LayoutTweaks.barInnerWidthScale) + padding * 2
    readonly property int contentShift: disabled ? contentWidth - chromeWidth : 0
    readonly property int exclusiveZone: !disabled && shouldBeVisible ? contentWidth : chromeWidth
    readonly property int hyprLeftReserve: exclusiveZone
    readonly property bool launcherUiPriority: (visibilities.launcher && Config.launcher.enabled) || visibilities.windowPicker
    readonly property bool shouldBeVisible: !fullscreen && !disabled && (Config.bar.persistent || visibilities.bar || (isHovered && !launcherUiPriority))
    property bool isHovered

    function closeTray(): void {
        (content.item as Bar)?.closeTray();
    }

    function checkPopout(y: real): void {
        (content.item as Bar)?.checkPopout(y);
    }

    function handleWheel(globalY: real, barX: real, barY: real, angleDelta: point): void {
        (content.item as Bar)?.handleWheel(globalY, barX, barY, angleDelta);
    }

    MouseArea {
        anchors.fill: parent
        z: 100
        enabled: root.visibilities.sidebar && Config.sidebar.enabled
        propagateComposedEvents: true
        onPressed: root.visibilities.sidebar = false
    }

    clip: true
    visible: width > 0
    implicitWidth: fullscreen ? 0 : (disabled ? chromeWidth : Config.border.thickness)

    states: State {
        name: "visible"
        when: root.shouldBeVisible

        PropertyChanges {
            root.implicitWidth: root.contentWidth
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitWidth"
                type: Anim.DefaultSpatial
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitWidth"
                type: Anim.Emphasized
            }
        }
    ]

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        x: -root.contentShift

        active: !root.disabled && (root.shouldBeVisible || root.visible)
        opacity: active ? 1 : 0

        sourceComponent: Bar {
            width: root.contentWidth
            screen: root.screen
            visibilities: root.visibilities
            popouts: root.popouts // qmllint disable incompatible-type
            fullscreen: root.fullscreen
        }
    }
}
