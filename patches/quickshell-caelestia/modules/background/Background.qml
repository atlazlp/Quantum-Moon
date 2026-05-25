pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.utils

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled !== false)

    StyledWindow {
        id: win

        required property ShellScreen modelData

        readonly property bool useQmSlot: !contentItem.Config.background.wallpaperEnabled && QuantumMoonWallpaper.shouldShowOnScreen(modelData.name)

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: contentItem.Config.background.wallpaperEnabled || useQmSlot ? WlrLayer.Background : WlrLayer.Bottom
        color: contentItem.Config.background.wallpaperEnabled || useQmSlot ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: contentItem.Config.background.wallpaperEnabled || win.useQmSlot

                sourceComponent: contentItem.Config.background.wallpaperEnabled ? caelestiaWallpaper : qmSlotWallpaper
            }

            Component {
                id: caelestiaWallpaper

                Wallpaper {}
            }

            Component {
                id: qmSlotWallpaper

                SlotWallpaper {
                    path: QuantumMoonWallpaper.slotPathForScreen(win.modelData.name)
                }
            }

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: wallpaper
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled !== false

            anchors.margins: Tokens.padding.large * 2
            anchors.leftMargin: {
                const chrome = Math.max(Config.border.minThickness, Config.border.thickness);
                const barInset = Strings.testRegexList(Config.bar.excludedScreens, win.modelData.name) ? chrome : Math.round(Tokens.sizes.bar.innerWidth * LayoutTweaks.barInnerWidthScale) + Math.max(Tokens.padding.smaller, Config.border.thickness);
                return Tokens.padding.large * 2 + barInset;
            }

            state: Config.background.desktopClock.position || "bottom-right"
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
