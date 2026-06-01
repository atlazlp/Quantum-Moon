pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property PopoutState popouts

    implicitWidth: 300
    implicitHeight: Math.min(outerCol.implicitHeight, 500)

    ColumnLayout {
        id: outerCol

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.normal
        spacing: Tokens.spacing.small

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: GitWatcher.overdueCount > 0 ? "data_alert"
                    : GitWatcher.prs.length > 0 ? "data_info_alert"
                    : "check"
                fill: 1
                color: GitWatcher.overdueCount > 0
                    ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                    : Colours.palette.m3secondary
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Azure DevOps")
                font.weight: 600
            }

            // Loading spinner
            MaterialIcon {
                visible: GitWatcher.loading
                text: "sync"
                color: Colours.palette.m3secondary
                opacity: 0.7
                RotationAnimation on rotation {
                    running: GitWatcher.loading
                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                }
            }

            // Count badge
            StyledRect {
                visible: GitWatcher.prs.length > 0
                implicitWidth: badgeLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: badgeLabel.implicitHeight + 2
                radius: Tokens.rounding.full
                color: GitWatcher.overdueCount > 0
                    ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                    : Colours.palette.m3primaryContainer

                StyledText {
                    id: badgeLabel
                    anchors.centerIn: parent
                    text: GitWatcher.prs.length.toString()
                    font.pixelSize: Tokens.font.sizes.small
                    color: GitWatcher.overdueCount > 0 ? "white" : Colours.palette.m3onPrimaryContainer
                }
            }
        }

        // Error
        StyledText {
            visible: GitWatcher.lastError.length > 0
            Layout.fillWidth: true
            text: GitWatcher.lastError
            color: Colours.palette.m3error
            font.pixelSize: Tokens.font.sizes.small
            wrapMode: Text.WordWrap
        }

        // ── Tab bar ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.smaller

            Repeater {
                model: [
                    { key: 0, label: qsTr("PRs"),      count: GitWatcher.prs.length },
                    { key: 1, label: qsTr("Comments"), count: GitWatcher.commentItems.length },
                    { key: 2, label: qsTr("Mentions"), count: GitWatcher.mentionItems.length },
                ]

                Item {
                    id: tabItem

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: tabRow.implicitHeight + Tokens.padding.small * 2

                    readonly property bool active: tabBar.currentTab === modelData.key

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: tabItem.active
                            ? Colours.palette.m3primaryContainer
                            : Colours.tPalette.m3surfaceVariant
                        opacity: tabItem.active ? 1 : 0.6

                        Behavior on color { Anim { type: Anim.StandardSmall } }
                    }

                    RowLayout {
                        id: tabRow

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.padding.small
                        spacing: 3

                        StyledText {
                            Layout.fillWidth: true
                            text: tabItem.modelData.label
                            font.pixelSize: Tokens.font.sizes.small
                            font.weight: tabItem.active ? 600 : 400
                            color: tabItem.active
                                ? Colours.palette.m3onPrimaryContainer
                                : Colours.palette.m3onSurface
                            horizontalAlignment: Text.AlignHCenter
                        }

                        StyledRect {
                            visible: tabItem.modelData.count > 0
                            implicitWidth: cntLbl.implicitWidth + 6
                            implicitHeight: cntLbl.implicitHeight + 2
                            radius: Tokens.rounding.full
                            color: tabItem.active
                                ? Colours.palette.m3primary
                                : Colours.palette.m3surfaceVariant

                            StyledText {
                                id: cntLbl
                                anchors.centerIn: parent
                                text: tabItem.modelData.count.toString()
                                font.pixelSize: Tokens.font.sizes.small - 1
                                color: tabItem.active ? "white" : Colours.palette.m3secondary
                            }
                        }
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: Colours.palette.m3onSurface
                        onClicked: tabBar.currentTab = tabItem.modelData.key
                    }
                }
            }
        }

        // Tab controller (no visual, just state)
        QtObject {
            id: tabBar
            property int currentTab: 0
        }

        // ── Content area ─────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.min(contentStack.implicitHeight, 340)
            clip: true

            Item {
                id: contentStack

                anchors.left: parent.left
                anchors.right: parent.right
                // Height is the max of all three tabs
                implicitHeight: Math.max(prListItem.implicitHeight,
                                         commentListItem.implicitHeight,
                                         mentionListItem.implicitHeight)

                // PRs tab
                FeedList {
                    id: prListItem
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: tabBar.currentTab === 0
                    model: GitWatcher.prs
                    emptyText: qsTr("No active PRs")
                    delegate: prDelegate
                }

                // Comments tab
                FeedList {
                    id: commentListItem
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: tabBar.currentTab === 1
                    model: GitWatcher.commentItems
                    emptyText: qsTr("No new comments")
                    delegate: feedItemDelegate
                }

                // Mentions tab
                FeedList {
                    id: mentionListItem
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: tabBar.currentTab === 2
                    model: GitWatcher.mentionItems
                    emptyText: qsTr("No mentions")
                    delegate: feedItemDelegate
                }
            }
        }

        // ── Footer buttons ───────────────────────────────────────────────────
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

    // ── Delegates ─────────────────────────────────────────────────────────────

    Component {
        id: prDelegate

        Item {
            id: prRow

            required property var modelData

            width: ListView.view?.width ?? 0
            implicitHeight: prRowInner.implicitHeight + Tokens.padding.small * 2

            readonly property bool isOverdue: modelData.isOverdue ?? false

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

            ColumnLayout {
                id: prRowInner

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    MaterialIcon {
                        visible: prRow.modelData.hasMentions || prRow.modelData.hasUnreadComments
                        text: prRow.modelData.hasMentions ? "mark_unread_chat_alt" : "chat"
                        color: prRow.modelData.hasMentions
                            ? (GitWatcher._configData?.colors?.mention ?? "#e53935")
                            : Colours.palette.m3secondary
                        font.pixelSize: Tokens.font.sizes.small
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: prRow.modelData.title
                        elide: Text.ElideRight
                        font.weight: prRow.modelData.isOwned ? 600 : 400
                    }

                    StyledText {
                        text: prRow.isOverdue
                            ? qsTr("stalled %1").arg(_formatAge(prRow.modelData.stallMinutes ?? prRow.modelData.ageMinutes))
                            : _formatAge(prRow.modelData.ageMinutes)
                        font.pixelSize: Tokens.font.sizes.small
                        color: prRow.isOverdue
                            ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                            : Colours.palette.m3secondary
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    StyledText {
                        text: prRow.modelData.repo
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.maximumWidth: 120
                    }

                    StyledText { text: "→"; font.pixelSize: Tokens.font.sizes.small; color: Colours.palette.m3secondary }

                    StyledText {
                        text: prRow.modelData.targetBranch
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.maximumWidth: 100
                    }
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

    Component {
        id: feedItemDelegate

        Item {
            id: feedRow

            required property var modelData

            width: ListView.view?.width ?? 0
            implicitHeight: feedInner.implicitHeight + Tokens.padding.small * 2

            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceVariant
                opacity: 0.8
            }

            ColumnLayout {
                id: feedInner

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    StyledText {
                        text: feedRow.modelData.author
                        font.weight: 500
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3primary
                        elide: Text.ElideRight
                        Layout.maximumWidth: 100
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "· " + feedRow.modelData.prTitle
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: feedRow.modelData.excerpt
                    font.pixelSize: Tokens.font.sizes.small - 1
                    color: Colours.palette.m3onSurface
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }

            StateLayer {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: Colours.palette.m3onSurface
                onClicked: Qt.openUrlExternally(feedRow.modelData.url)
            }
        }
    }

    // ── Scrollable feed list helper ───────────────────────────────────────────
    component FeedList: ListView {
        required property Component delegate
        required property string emptyText

        implicitHeight: contentHeight > 0 ? Math.min(contentHeight, 340) : emptyItem.implicitHeight + Tokens.padding.small * 2
        spacing: Tokens.spacing.smaller
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: emptyItem

            anchors.fill: parent
            visible: parent.count === 0

            StyledText {
                anchors.centerIn: parent
                text: parent.parent?.emptyText ?? ""
                color: Colours.palette.m3secondary
                font.pixelSize: Tokens.font.sizes.small
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _formatAge(minutes: int): string {
        if (minutes < 60)
            return qsTr("%1m").arg(minutes);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return m > 0 ? qsTr("%1h%2m").arg(h).arg(m) : qsTr("%1h").arg(h);
    }

    function _formatTimestamp(iso: string): string {
        if (!iso) return "";
        try {
            return new Date(iso).toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
        } catch (e) {
            return iso;
        }
    }
}
