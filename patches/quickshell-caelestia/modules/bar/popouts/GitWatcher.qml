pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.platform as Platform
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: layout.implicitWidth + Tokens.padding.normal * 2
    implicitHeight: Math.min(layout.implicitHeight + Tokens.padding.normal * 2, 480)

    // -----------------------------------------------------------------------
    // Header
    // -----------------------------------------------------------------------
    ColumnLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.normal
        spacing: Tokens.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "fork_right"
                fill: 1
                color: Colours.palette.m3secondary
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Azure DevOps PRs")
                font.weight: 600
            }

            // Count badge
            StyledRect {
                visible: GitWatcher.prs.length > 0

                implicitWidth: countLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: countLabel.implicitHeight + 2
                radius: Tokens.rounding.full
                color: GitWatcher.overdueCount > 0
                    ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                    : GitWatcher.mentionCount > 0
                      ? (GitWatcher._configData?.colors?.mention ?? "#e53935")
                      : Colours.palette.m3primaryContainer

                StyledText {
                    id: countLabel

                    anchors.centerIn: parent
                    text: GitWatcher.prs.length.toString()
                    font.pixelSize: Tokens.font.sizes.small
                    color: GitWatcher.overdueCount > 0 || GitWatcher.mentionCount > 0
                        ? "white"
                        : Colours.palette.m3onPrimaryContainer
                }
            }

            // Spinning indicator while loading
            MaterialIcon {
                visible: GitWatcher.loading
                text: "sync"
                color: Colours.palette.m3secondary
                opacity: 0.7

                RotationAnimation on rotation {
                    running: GitWatcher.loading
                    from: 0; to: 360
                    duration: 1000
                    loops: Animation.Infinite
                }
            }
        }

        // Error message
        StyledText {
            visible: GitWatcher.lastError.length > 0
            Layout.fillWidth: true
            text: GitWatcher.lastError
            color: Colours.palette.m3error
            font.pixelSize: Tokens.font.sizes.small
            wrapMode: Text.WordWrap
        }

        // -----------------------------------------------------------------------
        // PR list
        // -----------------------------------------------------------------------
        Item {
            id: listContainer

            Layout.fillWidth: true
            implicitHeight: prList.implicitHeight
            // Clamp to avoid oversized popout
            height: Math.min(implicitHeight, 340)
            clip: true
            visible: GitWatcher.prs.length > 0

            ListView {
                id: prList

                anchors.fill: parent
                spacing: Tokens.spacing.smaller
                model: GitWatcher.prs
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: prRow

                    required property var modelData
                    required property int index

                    width: prList.width
                    implicitHeight: prRowLayout.implicitHeight + Tokens.padding.small * 2

                    readonly property bool isOverdue: modelData.ageMinutes >= (GitWatcher._configData?.notifications?.overdueMinutes ?? 60)

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: prRow.isOverdue
                            ? Qt.rgba(1, 0.59, 0, 0.12)
                            : prRow.modelData.hasMentions
                              ? Qt.rgba(0.9, 0.2, 0.2, 0.1)
                              : Colours.tPalette.m3surfaceVariant
                        opacity: 0.9
                    }

                    RowLayout {
                        id: prRowLayout

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.small
                        spacing: Tokens.spacing.smaller

                        // Mention / owned indicator
                        MaterialIcon {
                            visible: prRow.modelData.hasMentions || prRow.modelData.hasUnreadComments
                            text: prRow.modelData.hasMentions ? "mark_unread_chat_alt" : "chat"
                            color: prRow.modelData.hasMentions
                                ? (GitWatcher._configData?.colors?.mention ?? "#e53935")
                                : Colours.palette.m3secondary
                            font.pixelSize: Tokens.font.sizes.small
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: prRow.modelData.title
                                elide: Text.ElideRight
                                font.weight: prRow.modelData.isOwned ? 600 : 400
                            }

                            RowLayout {
                                spacing: Tokens.spacing.smaller

                                // Repo chip
                                StyledText {
                                    text: prRow.modelData.repo
                                    font.pixelSize: Tokens.font.sizes.small
                                    color: Colours.palette.m3secondary
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 120
                                }

                                StyledText {
                                    text: "→"
                                    font.pixelSize: Tokens.font.sizes.small
                                    color: Colours.palette.m3secondary
                                }

                                StyledText {
                                    text: prRow.modelData.targetBranch
                                    font.pixelSize: Tokens.font.sizes.small
                                    color: Colours.palette.m3secondary
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 100
                                }
                            }
                        }

                        // Age label
                        StyledText {
                            text: _formatAge(prRow.modelData.ageMinutes)
                            font.pixelSize: Tokens.font.sizes.small
                            color: prRow.isOverdue
                                ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                                : Colours.palette.m3secondary
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3onSurface
                        onClicked: Qt.openUrlExternally(prRow.modelData.url)
                    }
                }
            }
        }

        // Empty state
        StyledText {
            visible: GitWatcher.prs.length === 0 && GitWatcher.lastError.length === 0
            Layout.fillWidth: true
            text: qsTr("No active PRs")
            color: Colours.palette.m3secondary
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Tokens.font.sizes.small
        }

        // -----------------------------------------------------------------------
        // Footer buttons
        // -----------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.smaller
            spacing: Tokens.spacing.small

            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer
                verticalPadding: Tokens.padding.small
                text: qsTr("Refresh")
                icon: "sync"
                onClicked: GitWatcher.refresh()
            }

            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.small
                text: qsTr("Config")
                icon: "settings"
                onClicked: root.popouts.detachRequested("gitwatcher")
            }
        }

        // Last updated
        StyledText {
            visible: GitWatcher.lastUpdated.length > 0
            Layout.fillWidth: true
            text: qsTr("Updated %1").arg(_formatTimestamp(GitWatcher.lastUpdated))
            font.pixelSize: Tokens.font.sizes.small - 1
            color: Colours.palette.m3secondary
            opacity: 0.6
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    function _formatAge(minutes: int): string {
        if (minutes < 60)
            return qsTr("%1m").arg(minutes);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return m > 0 ? qsTr("%1h%2m").arg(h).arg(m) : qsTr("%1h").arg(h);
    }

    function _formatTimestamp(iso: string): string {
        if (!iso)
            return "";
        try {
            const d = new Date(iso);
            return d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        } catch (e) {
            return iso;
        }
    }
}
