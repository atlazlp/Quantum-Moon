pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property var panels
    required property real maxHeight
    required property var onKillRequest

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.large

    readonly property bool killDialogOpen: root.panels.windowPicker.killConfirmOpen

    function releaseKillDialogInput(): void {
        search.focus = false;
    }

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: searchWrapper.height + listWrapper.height + padding * 2

    Item {
        id: listWrapper

        implicitWidth: Tokens.sizes.launcher.itemWidth
        implicitHeight: list.implicitHeight + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: root.padding

        clip: true

        WindowList {
            id: list

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            search: search
            visibilities: root.visibilities
            onKillRequest: root.onKillRequest
            muteKeys: root.killDialogOpen
        }
    }

    StyledRect {
        id: searchWrapper

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Tokens.rounding.full

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding

        implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, clearIcon.implicitHeight)

        MaterialIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            text: "search"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: search

            readOnly: root.killDialogOpen

            anchors.left: searchIcon.right
            anchors.right: clearIcon.left
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.spacing.small

            topPadding: Tokens.padding.larger
            bottomPadding: Tokens.padding.larger

            placeholderText: qsTr("Filter windows…")

            onAccepted: {
                const md = list.currentItem?.modelData;
                if (md && md.address) {
                    Hypr.dispatch(`focuswindow address:0x${md.address}`);
                    root.visibilities.windowPicker = false;
                }
            }

            Keys.onUpPressed: {
                if (!root.killDialogOpen)
                    list.decrementCurrentIndex();
            }
            Keys.onDownPressed: {
                if (!root.killDialogOpen)
                    list.incrementCurrentIndex();
            }

            Keys.onEscapePressed: {
                if (!root.killDialogOpen)
                    root.visibilities.windowPicker = false;
            }

            Component.onCompleted: forceActiveFocus()

            Connections {
                function onWindowPickerChanged(): void {
                    if (!root.visibilities.windowPicker)
                        search.text = "";
                }

                target: root.visibilities
            }
        }

        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding

            width: search.text ? implicitWidth : implicitWidth / 2
            opacity: {
                if (!search.text)
                    return 0;
                if (mouse.pressed)
                    return 0.7;
                if (mouse.containsMouse)
                    return 0.8;
                return 1;
            }

            text: "close"
            color: Colours.palette.m3onSurfaceVariant

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: search.text ? Qt.PointingHandCursor : undefined

                onClicked: search.text = ""
            }

            Behavior on width {
                Anim {
                    type: Anim.StandardSmall
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardSmall
                }
            }
        }
    }
}
