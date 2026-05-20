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

    readonly property string windowKey: root.modelData?.klass ?? ""
    readonly property int killWidth: Tokens.sizes.launcher.itemHeight
    readonly property int settingsWidth: Tokens.sizes.launcher.itemHeight
    readonly property int actionWidth: root.rowHovered ? root.killWidth + root.settingsWidth : 0
    readonly property bool rowHovered: rowHover.hovered || killMouse.containsMouse || settingsMouse.containsMouse
    readonly property string defaultIcon: Icons.getAppIcon(root.windowKey, "image-missing")
    readonly property string defaultLabel: root.modelData?.line ?? ""
    readonly property string defaultSubtitle: root.modelData?.klass ?? ""
    readonly property string ramLabel: root.modelData?.ramLabel ?? ""
    readonly property int overrideRev: LauncherItemOverrides.revision

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    HoverHandler {
        id: rowHover
    }

    StateLayer {
        id: stateLayer

        anchors.fill: parent
        anchors.rightMargin: root.actionWidth
        radius: Tokens.rounding.normal
        onClicked: {
            if (LauncherItemOverrides.launcherJustCleared())
                return;
            Hypr.dispatch(`focuswindow address:${root.modelData.address}`);
            root.visibilities.windowPicker = false;
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger + root.actionWidth
        anchors.margins: Tokens.padding.smaller

        IconImage {
            id: icon

            asynchronous: true
            source: {
                const _r = root.overrideRev;
                return LauncherItemOverrides.iconSource("window", root.windowKey, root.defaultIcon);
            }
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

            implicitHeight: name.implicitHeight + subtitleRow.implicitHeight

            StyledText {
                id: name

                width: parent.width
                text: LauncherItemOverrides.displayLabel("window", root.windowKey, root.defaultLabel)
                font.pointSize: Tokens.font.size.normal
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Item {
                id: subtitleRow

                width: parent.width
                anchors.top: name.bottom
                implicitHeight: comment.implicitHeight

                StyledText {
                    id: comment

                    anchors.left: parent.left
                    anchors.right: ramLabel.visible ? ramLabel.left : parent.right
                    anchors.rightMargin: ramLabel.visible ? Tokens.spacing.small : 0
                    anchors.verticalCenter: parent.verticalCenter

                    text: LauncherItemOverrides.subtitle("window", root.windowKey, root.defaultSubtitle)
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3outline

                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                StyledText {
                    id: ramLabel

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter

                    text: root.ramLabel
                    visible: text.length > 0
                    font.pointSize: Tokens.font.size.small
                    color: Colours.palette.m3outline
                }
            }
        }
    }

    Item {
        id: settingsSection

        z: 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: killSection.left
        width: root.rowHovered ? root.settingsWidth : 0
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

        MaterialIcon {
            anchors.centerIn: parent
            text: "settings"
            color: Colours.palette.m3onSurfaceVariant
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
            id: settingsMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: mouse => {
                mouse.accepted = true;
                LauncherItemOverrides.openEditor({
                    type: "window",
                    key: root.windowKey,
                    screen: Config.screen,
                    defaultLabel: root.defaultLabel,
                    defaultSubtitle: root.defaultSubtitle,
                    defaultIcon: root.defaultIcon
                });
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
