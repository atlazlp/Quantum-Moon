pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen
    required property DrawerVisibilities visibilities

    Config.screen: root.screen.name

    readonly property int notifCount: Notifs.notClosed.length
    readonly property bool showNotifBadge: root.notifCount > 0 && Config.sidebar.enabled
    readonly property int wide: Math.round(Tokens.sizes.bar.innerWidth * LayoutTweaks.barInnerWidthScale)

    readonly property bool onSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name !== ""

    property real blur: onSpecial ? 1 : 0

    property real badgeBgOpacity: 1
    property real badgeBgScale: 1
    property real badgeNumOpacity: 1
    property int displayNotifCount: 0
    property bool prevWantsNotif: false
    property bool notifBootstrapped: false

    implicitWidth: wide
    implicitHeight: wide

    color: "transparent"
    radius: wide * 0.5

    function handleWorkspaceWheel(barRoot: Item, lx: real, ly: real, angleDelta: point): bool {
        if (!Config.bar.scrollActions.workspaces)
            return false;
        const lp = mapFromItem(barRoot, lx, ly);
        if (lp.x < 0 || lp.y < 0 || lp.x > width || lp.y > height)
            return false;
        const mon = Hypr.monitorFor(screen);
        const monName = mon.name;
        const specialWs = mon.lastIpcObject.specialWorkspace?.name ?? "";
        if (specialWs.length > 0) {
            Hypr.dispatch(`togglespecialworkspace ${specialWs.slice(8)}`);
            return true;
        }
        Hypr.dispatch(`focusmonitor ${monName}`);
        const cur = mon.activeWorkspace?.id ?? 1;
        if (angleDelta.y < 0 || cur > 1)
            Hypr.dispatch(`workspace r${angleDelta.y > 0 ? "-" : "+"}1`);
        return true;
    }

    StyledClippingRect {
        id: notifChipBg

        anchors.fill: parent
        z: -1
        color: Colours.tPalette.m3surfaceContainer
        radius: root.wide * 0.5
        opacity: root.onSpecial ? 1 : root.badgeBgOpacity
        scale: root.onSpecial ? 1 : root.badgeBgScale
        transformOrigin: Item.Center
    }

    SequentialAnimation {
        id: notifEnterAnim

        ScriptAction {
            script: {
                root.badgeBgOpacity = 0;
                root.badgeBgScale = 0.55;
                root.badgeNumOpacity = 0;
            }
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "badgeBgOpacity"
                to: 1
                duration: 175
                easing.type: Easing.OutCubic
            }

            NumberAnimation {
                target: root
                property: "badgeBgScale"
                to: 1
                duration: 175
                easing.type: Easing.OutCubic
            }
        }

        NumberAnimation {
            target: root
            property: "badgeNumOpacity"
            to: 1
            duration: 125
            easing.type: Easing.OutQuad
        }
    }

    SequentialAnimation {
        id: notifExitAnim

        NumberAnimation {
            target: root
            property: "badgeNumOpacity"
            to: 0
            duration: 95
            easing.type: Easing.OutQuad
        }

        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "badgeBgOpacity"
                to: 0
                duration: 190
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: root
                property: "badgeBgScale"
                to: 0.82
                duration: 190
                easing.type: Easing.InQuad
            }
        }

        ScriptAction {
            script: root.displayNotifCount = 0
        }
    }

    Component.onCompleted: {
        root.displayNotifCount = root.notifCount > 0 ? root.notifCount : 0;
        if (root.onSpecial || root.showNotifBadge) {
            root.badgeBgOpacity = 1;
            root.badgeBgScale = 1;
            root.badgeNumOpacity = root.showNotifBadge ? 1 : 0;
        } else {
            root.badgeBgOpacity = 0;
            root.badgeBgScale = 0.85;
            root.badgeNumOpacity = 0;
        }
        root.prevWantsNotif = root.showNotifBadge;
        root.notifBootstrapped = true;
    }

    Connections {
        target: root

        function onShowNotifBadgeChanged(): void {
            if (!root.notifBootstrapped)
                return;
            if (root.onSpecial) {
                root.prevWantsNotif = root.showNotifBadge;
                root.badgeNumOpacity = root.showNotifBadge ? 1 : 0;
                return;
            }
            if (root.showNotifBadge && !root.prevWantsNotif) {
                notifExitAnim.stop();
                root.displayNotifCount = root.notifCount;
                notifEnterAnim.restart();
            } else if (!root.showNotifBadge && root.prevWantsNotif) {
                notifEnterAnim.stop();
                notifExitAnim.restart();
            }
            root.prevWantsNotif = root.showNotifBadge;
        }

        function onNotifCountChanged(): void {
            if (root.notifCount > 0)
                root.displayNotifCount = root.notifCount;
        }

        function onOnSpecialChanged(): void {
            if (!root.notifBootstrapped)
                return;
            notifEnterAnim.stop();
            notifExitAnim.stop();
            if (root.onSpecial) {
                root.badgeBgOpacity = 1;
                root.badgeBgScale = 1;
                root.badgeNumOpacity = root.showNotifBadge ? 1 : 0;
            } else if (!root.showNotifBadge) {
                root.badgeBgOpacity = 0;
                root.badgeBgScale = 0.85;
                root.badgeNumOpacity = 0;
            } else {
                root.badgeBgOpacity = 1;
                root.badgeBgScale = 1;
                root.badgeNumOpacity = 1;
            }
        }
    }

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Item {
            id: dotCell

            anchors.fill: parent

            StyledText {
                id: badgeLabel

                visible: root.displayNotifCount > 0
                opacity: root.badgeNumOpacity
                anchors.fill: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.NoWrap
                text: root.displayNotifCount > 99 ? "99+" : String(root.displayNotifCount)
                font.pointSize: root.displayNotifCount > 9 ? Math.round(Tokens.font.size.smaller * 0.9) : Tokens.font.size.smaller
                font.bold: true
                color: Colours.layer(Colours.palette.m3primary, 2)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false)
                        return;
                    root.visibilities.sidebar = !root.visibilities.sidebar;
                }
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {}
        }
    }

    Loader {
        id: specialWs

        asynchronous: true

        anchors.fill: parent
        anchors.margins: Tokens.padding.small

        active: opacity > 0

        scale: root.onSpecial ? 1 : 0.5
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: SpecialWorkspaces {
            screen: root.screen
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {}
        }
    }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
