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

    // Fixed size — ListView scrolls within the content area.
    // 320 × 580 gives room for ~12 PR rows before scrolling.
    implicitWidth: 320
    implicitHeight: 580

    ColumnLayout {
        anchors.fill: parent
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

        // Error banner
        StyledText {
            visible: GitWatcher.lastError.length > 0
            Layout.fillWidth: true
            text: GitWatcher.lastError
            color: Colours.palette.m3error
            font.pixelSize: Tokens.font.sizes.small
            wrapMode: Text.WordWrap
        }

        // ── Tabs ─────────────────────────────────────────────────────────────
        // Fixed-height row; each tab cell is the same size.
        // Content is centered using Row { anchors.centerIn } so presence or
        // absence of the count badge doesn't affect alignment.
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.smaller

            Repeater {
                id: tabRepeater

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
                    implicitHeight: 30

                    readonly property bool isActive: tabBar.currentTab === modelData.key

                    StyledRect {
                        anchors.fill: parent
                        radius: Tokens.rounding.small
                        color: tabItem.isActive
                            ? Colours.palette.m3primary
                            : Colours.tPalette.m3surfaceVariant
                        opacity: tabItem.isActive ? 1 : 0.6
                        Behavior on color { Anim { type: Anim.StandardSmall } }
                    }

                    // Centered content regardless of badge visibility
                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tabItem.modelData.label
                            font.pixelSize: Tokens.font.sizes.small
                            font.weight: tabItem.isActive ? 600 : 400
                            color: tabItem.isActive
                                ? Colours.palette.m3onPrimary
                                : Colours.palette.m3onSurface
                        }

                        StyledRect {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tabItem.modelData.count > 0
                            width: cntLbl.implicitWidth + 6
                            height: cntLbl.implicitHeight + 2
                            radius: Tokens.rounding.full
                            color: tabItem.isActive ? Colours.palette.m3onPrimary : Colours.palette.m3surfaceVariant

                            StyledText {
                                id: cntLbl
                                anchors.centerIn: parent
                                text: tabItem.modelData.count.toString()
                                font.pixelSize: Tokens.font.sizes.small - 1
                                color: tabItem.isActive ? Colours.palette.m3primary : Colours.palette.m3secondary
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

        QtObject { id: tabBar; property int currentTab: 0 }

        // ── Content — fills all remaining height ─────────────────────────────
        FeedList {
            id: prListItem
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tabBar.currentTab === 0
            listModel: GitWatcher.prs
            emptyText: qsTr("No active PRs")
            listDelegate: prDelegate
        }

        FeedList {
            id: commentListItem
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tabBar.currentTab === 1
            listModel: GitWatcher.commentItems
            emptyText: qsTr("No new comments")
            listDelegate: feedItemDelegate
        }

        FeedList {
            id: mentionListItem
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: tabBar.currentTab === 2
            listModel: GitWatcher.mentionItems
            emptyText: qsTr("No mentions")
            listDelegate: feedItemDelegate
        }

        // ── Footer ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
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

    // ── FeedList component ────────────────────────────────────────────────────
    // Uses an Item wrapper (NOT a ListView subclass) so that listModel and
    // listDelegate are plain properties that are explicitly forwarded to the
    // internal ListView — no property shadowing, no implicit height collapse.
    component FeedList: Item {
        id: fl

        required property var listModel
        required property Component listDelegate
        required property string emptyText

        clip: true

        ListView {
            id: innerList
            anchors.fill: parent
            model: fl.listModel
            delegate: fl.listDelegate
            spacing: Tokens.spacing.smaller
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        }

        StyledText {
            anchors.centerIn: parent
            visible: innerList.count === 0
            text: fl.emptyText
            color: Colours.palette.m3secondary
            font.pixelSize: Tokens.font.sizes.small
        }
    }

    // ── PR row delegate ───────────────────────────────────────────────────────
    Component {
        id: prDelegate

        Item {
            id: prRow

            required property var modelData

            width: ListView.view?.width ?? 0
            implicitHeight: prInner.implicitHeight + Tokens.padding.small * 2

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
                id: prInner

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

    // ── Comment/mention row delegate ──────────────────────────────────────────
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

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _formatAge(minutes: int): string {
        if (minutes < 60) return qsTr("%1m").arg(minutes);
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
