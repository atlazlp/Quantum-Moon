pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property DesktopEntry modelData
    required property DrawerVisibilities visibilities

    readonly property string appKey: root.modelData?.id ?? ""
    readonly property int settingsWidth: Tokens.sizes.launcher.itemHeight
    readonly property bool rowHovered: rowHover.hovered || settingsMouse.containsMouse
    readonly property string defaultIcon: Quickshell.iconPath(root.modelData?.icon, "image-missing")
    readonly property string defaultLabel: root.modelData?.name ?? ""
    readonly property string defaultSubtitle: (root.modelData?.comment || root.modelData?.genericName || root.modelData?.name) ?? ""
    readonly property int overrideRev: LauncherItemOverrides.revision

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    HoverHandler {
        id: rowHover
    }

    StateLayer {
        radius: Tokens.rounding.normal
        anchors.rightMargin: root.rowHovered ? root.settingsWidth : 0
        onPressed: mouse => {
            mouse.accepted = true;
            root.visibilities.windowPicker = false;
            Apps.launch(root.modelData);
            LauncherItemOverrides.noteLaunch(root.visibilities);
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.larger
        anchors.rightMargin: Tokens.padding.larger + (root.rowHovered ? root.settingsWidth : 0)
        anchors.margins: Tokens.padding.smaller

        IconImage {
            id: icon

            asynchronous: true
            source: {
                const _r = root.overrideRev;
                return LauncherItemOverrides.iconSource("app", root.appKey, root.defaultIcon);
            }
            implicitSize: parent.height * 0.8

            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            anchors.left: icon.right
            anchors.leftMargin: Tokens.spacing.normal
            anchors.verticalCenter: icon.verticalCenter

            implicitWidth: parent.width - icon.width - favouriteIcon.width
            implicitHeight: name.implicitHeight + comment.implicitHeight

            StyledText {
                id: name

                text: LauncherItemOverrides.displayLabel("app", root.appKey, root.defaultLabel)
                font.pointSize: Tokens.font.size.normal
            }

            StyledText {
                id: comment

                text: LauncherItemOverrides.subtitle("app", root.appKey, root.defaultSubtitle)
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline

                elide: Text.ElideRight
                width: root.width - icon.width - favouriteIcon.width - Tokens.rounding.normal * 2

                anchors.top: name.bottom
            }
        }

        Loader {
            id: favouriteIcon

            asynchronous: true
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            active: root.modelData && Strings.testRegexList(GlobalConfig.launcher.favouriteApps, root.modelData.id)

            sourceComponent: MaterialIcon {
                text: "favorite"
                fill: 1
                color: Colours.palette.m3primary
            }
        }
    }

    Item {
        id: settingsSection

        z: 1
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
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
                    type: "app",
                    key: root.appKey,
                    screen: Config.screen,
                    defaultLabel: root.defaultLabel,
                    defaultSubtitle: root.defaultSubtitle,
                    defaultIcon: root.defaultIcon
                });
            }
        }
    }
}
