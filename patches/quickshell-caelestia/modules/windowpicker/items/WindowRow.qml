pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property var modelData
    required property DrawerVisibilities visibilities
    required property var onKillRequest

    readonly property int killWidth: Tokens.sizes.launcher.itemHeight
    readonly property bool rowHovered: rowHover.hovered || killMouse.containsMouse

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    HoverHandler {
        id: rowHover
    }

    StateLayer {
        id: stateLayer

        anchors.fill: parent
        anchors.rightMargin: root.rowHovered ? root.killWidth : 0
        radius: Tokens.rounding.normal
        onClicked: {
            Hypr.dispatch(`focuswindow address:0x${root.modelData.address}`);
            root.visibilities.windowPicker = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger + (root.rowHovered ? root.killWidth : 0)
        anchors.margins: Tokens.padding.smaller

        IconImage {
            id: icon

            asynchronous: true
            source: Icons.getAppIcon(root.modelData?.klass ?? "", "image-missing")
            implicitSize: parent.height * 0.8

            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            id: textColumn

            anchors.left: icon.right
            anchors.right: parent.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.rightMargin: Tokens.padding.larger
            anchors.verticalCenter: icon.verticalCenter

            implicitHeight: name.implicitHeight + comment.implicitHeight

            StyledText {
                id: name

                width: parent.width
                text: root.modelData?.line ?? ""
                font.pointSize: Tokens.font.size.normal
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            StyledText {
                id: comment

                width: parent.width
                anchors.top: name.bottom

                text: root.modelData?.klass ?? ""
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
        }
    }

    Item {
        id: killSection

        z: 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.rowHovered ? root.killWidth : 0
        clip: true
        opacity: root.rowHovered ? 1 : 0

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

        StyledRect {
            anchors.fill: parent
            radius: Tokens.rounding.normal
            color: Colours.palette.m3error
        }

        MaterialIcon {
            id: killIcon

            anchors.centerIn: parent
            text: "close"
            color: Colours.palette.m3onError
            opacity: root.rowHovered ? 1 : 0
            scale: root.rowHovered ? 1 : 0.55

            Behavior on opacity {
                Anim {
                    type: Anim.StandardSmall
                }
            }

            Behavior on scale {
                Anim {
                    type: Anim.StandardSmall
                }
            }
        }

        MouseArea {
            id: killMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: mouse => {
                mouse.accepted = true;
                if (typeof root.onKillRequest === "function")
                    root.onKillRequest(root.modelData);
            }
        }
    }
}
