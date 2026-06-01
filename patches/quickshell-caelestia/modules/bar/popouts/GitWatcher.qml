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

    implicitWidth: 400
    implicitHeight: 620

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.normal
        spacing: Tokens.spacing.small

        // ── Header ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: GitWatcher.filteredOverdueCount > 0 ? "data_alert"
                    : GitWatcher.mainFeedItems.length > 0 ? "data_info_alert"
                    : "check"
                fill: 1
                color: GitWatcher.filteredOverdueCount > 0
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
                text: "sync"; color: Colours.palette.m3secondary; opacity: 0.7
                RotationAnimation on rotation {
                    running: GitWatcher.loading
                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                }
            }

            StyledRect {
                visible: GitWatcher.attentionCount > 0
                implicitWidth: attnLbl.implicitWidth + Tokens.padding.small * 2
                implicitHeight: attnLbl.implicitHeight + 2
                radius: Tokens.rounding.full
                color: GitWatcher.filteredOverdueCount > 0
                    ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                    : Colours.palette.m3primaryContainer

                StyledText {
                    id: attnLbl
                    anchors.centerIn: parent
                    text: GitWatcher.attentionCount.toString()
                    font.pixelSize: Tokens.font.sizes.small
                    color: GitWatcher.filteredOverdueCount > 0 ? "white" : Colours.palette.m3onPrimaryContainer
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
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.smaller

            Repeater {
                model: [
                    { key: 0, label: qsTr("Feed"),     count: GitWatcher.mainFeedItems.length },
                    { key: 1, label: qsTr("Archived"), count: GitWatcher.archiveFeedItems.length },
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
                    }

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

        // ── Content ──────────────────────────────────────────────────────────
        FeedList {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: tabBar.currentTab === 0
            listModel: GitWatcher.mainFeedItems
            emptyText: qsTr("Nothing to review")
            listDelegate: feedDelegate
        }

        FeedList {
            Layout.fillWidth: true; Layout.fillHeight: true
            visible: tabBar.currentTab === 1
            listModel: GitWatcher.archiveFeedItems
            emptyText: qsTr("No archived items")
            listDelegate: archiveDelegate
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
                text: qsTr("Refresh"); icon: "sync"
                onClicked: GitWatcher.refresh()
            }

            IconTextButton {
                Layout.fillWidth: true
                inactiveColour: Colours.palette.m3primaryContainer
                inactiveOnColour: Colours.palette.m3onPrimaryContainer
                verticalPadding: Tokens.padding.small
                text: qsTr("Config"); icon: "settings"
                onClicked: root.popouts.detachRequested("gitwatcher")
            }
        }

        StyledText {
            visible: GitWatcher.lastUpdated.length > 0
            Layout.fillWidth: true
            text: qsTr("Updated %1").arg(_fmtTime(GitWatcher.lastUpdated))
            font.pixelSize: Tokens.font.sizes.small - 1
            color: Colours.palette.m3secondary; opacity: 0.6
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── FeedList ─────────────────────────────────────────────────────────────
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

    // ── Main feed delegate ────────────────────────────────────────────────────
    // Covers itemType: "pr", "comment", "mention"
    Component {
        id: feedDelegate

        Item {
            id: card

            required property var modelData

            width: ListView.view?.width ?? 0

            // Action strip height (slides in on hover)
            property bool showActions: hov.hovered

            implicitHeight: cardInner.implicitHeight + actionArea.implicitHeight +
                            Tokens.padding.normal * 2  // generous vertical padding

            HoverHandler { id: hov }

            // Card background
            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.normal
                color: {
                    if (card.modelData.itemType === "pr") {
                        if (card.modelData.isOverdue)   return Qt.rgba(1, 0.59, 0, 0.14);
                        if (card.modelData.hasMentions) return Qt.rgba(0.9, 0.2, 0.2, 0.10);
                    }
                    if (card.modelData.itemType === "mention") return Qt.rgba(0.9, 0.2, 0.2, 0.10);
                    return Colours.tPalette.m3surfaceVariant;
                }
                opacity: card.modelData.isMuted ? 0.5 : 0.85
            }

            ColumnLayout {
                id: cardInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.normal
                spacing: Tokens.spacing.smaller

                // ── PR card content ──
                RowLayout {
                    visible: card.modelData.itemType === "pr"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    // Type chip
                    StyledRect {
                        implicitWidth: chipLabel.implicitWidth + 8
                        implicitHeight: chipLabel.implicitHeight + 3
                        radius: Tokens.rounding.full
                        color: card.modelData.isOverdue
                            ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                            : card.modelData.hasMentions
                              ? (GitWatcher._configData?.colors?.mention ?? "#e53935")
                              : Colours.palette.m3surfaceVariant

                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: card.modelData.isOverdue ? qsTr("stalled") :
                                  card.modelData.hasMentions ? qsTr("mention") :
                                  card.modelData.hasUnreadComments ? qsTr("comment") :
                                  card.modelData.isOwned ? qsTr("mine") : qsTr("PR")
                            font.pixelSize: Tokens.font.sizes.small - 1
                            color: (card.modelData.isOverdue || card.modelData.hasMentions)
                                ? "white" : Colours.palette.m3secondary
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.title
                        elide: Text.ElideRight
                        font.weight: card.modelData.isOwned ? 600 : 400
                    }

                    StyledText {
                        text: card.modelData.isOverdue
                            ? qsTr("⚠ %1").arg(_fmtAge(card.modelData.stallMinutes ?? card.modelData.ageMinutes))
                            : _fmtAge(card.modelData.ageMinutes)
                        font.pixelSize: Tokens.font.sizes.small
                        color: card.modelData.isOverdue
                            ? (GitWatcher._configData?.colors?.overdue ?? "#ff9500")
                            : Colours.palette.m3secondary
                    }
                }

                RowLayout {
                    visible: card.modelData.itemType === "pr"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    StyledText {
                        text: (card.modelData.project !== "" ? card.modelData.project + " · " : "") + card.modelData.repo
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: "→ " + card.modelData.targetBranch
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                        elide: Text.ElideRight
                        Layout.maximumWidth: 110
                    }
                }

                // ── Comment / Mention card content ──
                RowLayout {
                    visible: card.modelData.itemType === "comment" || card.modelData.itemType === "mention"
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.smaller

                    MaterialIcon {
                        text: card.modelData.itemType === "mention" ? "alternate_email" : "chat"
                        color: card.modelData.itemType === "mention"
                            ? (GitWatcher._configData?.colors?.mention ?? "#e53935")
                            : Colours.palette.m3secondary
                        font.pixelSize: Tokens.font.sizes.normal
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.smaller

                            StyledText {
                                text: card.modelData.author ?? ""
                                font.weight: 500
                                font.pixelSize: Tokens.font.sizes.small
                                color: Colours.palette.m3primary
                                elide: Text.ElideRight
                                Layout.maximumWidth: 100
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: "· " + (card.modelData.title ?? "")
                                font.pixelSize: Tokens.font.sizes.small
                                color: Colours.palette.m3secondary
                                elide: Text.ElideRight
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.excerpt ?? ""
                            font.pixelSize: Tokens.font.sizes.small - 1
                            color: Colours.palette.m3onSurface
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── Action strip (slides in on hover) ────────────────────────────
            Item {
                id: actionArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: cardInner.bottom
                anchors.topMargin: card.showActions ? Tokens.spacing.smaller : 0

                implicitHeight: card.showActions ? actionRow.implicitHeight + Tokens.padding.small : 0
                clip: true
                opacity: card.showActions ? 1 : 0

                Behavior on implicitHeight { Anim { type: Anim.StandardSmall } }
                Behavior on opacity { Anim { type: Anim.StandardSmall } }

                RowLayout {
                    id: actionRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.padding.normal
                    anchors.rightMargin: Tokens.padding.normal
                    spacing: Tokens.spacing.small

                    // Open in browser
                    Item {
                        implicitWidth: openIcon.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: openIcon.implicitHeight + Tokens.padding.small
                        MaterialIcon { id: openIcon; anchors.centerIn: parent; text: "open_in_new"; color: Colours.palette.m3secondary; font.pixelSize: Tokens.font.sizes.normal }
                        StateLayer { anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.palette.m3onSurface; onClicked: Qt.openUrlExternally(card.modelData.url) }
                    }

                    Item { Layout.fillWidth: true }

                    // Mute / Unmute
                    Item {
                        implicitWidth: muteRow.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: muteRow.implicitHeight + Tokens.padding.small

                        RowLayout {
                            id: muteRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialIcon { text: card.modelData.isMuted ? "notifications_off" : "notifications"; color: Colours.palette.m3secondary; font.pixelSize: Tokens.font.sizes.normal }
                            StyledText { text: card.modelData.isMuted ? qsTr("Unmute") : qsTr("Mute"); font.pixelSize: Tokens.font.sizes.small; color: Colours.palette.m3secondary }
                        }

                        StateLayer {
                            anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.palette.m3onSurface
                            onClicked: {
                                if (card.modelData.isMuted) GitWatcher.unmute(card.modelData.prId);
                                else GitWatcher.mute(card.modelData.prId);
                            }
                        }
                    }

                    // Dismiss
                    Item {
                        implicitWidth: dismissRow.implicitWidth + Tokens.padding.small * 2
                        implicitHeight: dismissRow.implicitHeight + Tokens.padding.small

                        RowLayout {
                            id: dismissRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialIcon { text: "archive"; color: Colours.palette.m3error; font.pixelSize: Tokens.font.sizes.normal }
                            StyledText { text: qsTr("Dismiss"); font.pixelSize: Tokens.font.sizes.small; color: Colours.palette.m3error }
                        }

                        StateLayer {
                            anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.palette.m3onSurface
                            onClicked: GitWatcher.dismiss(card.modelData.prId)
                        }
                    }
                }
            }

            // Tap/click whole card to open URL.
            // Disabled when actions are visible so the action buttons can receive clicks.
            StateLayer {
                anchors.fill: parent; radius: Tokens.rounding.normal; color: Colours.palette.m3onSurface
                enabled: !card.showActions
                onClicked: Qt.openUrlExternally(card.modelData.url)
            }
        }
    }

    // ── Archive delegate ──────────────────────────────────────────────────────
    // Simpler card, no hover actions
    Component {
        id: archiveDelegate

        Item {
            id: archCard

            required property var modelData

            width: ListView.view?.width ?? 0
            implicitHeight: archInner.implicitHeight + Tokens.padding.normal * 2

            StyledRect {
                anchors.fill: parent; radius: Tokens.rounding.normal
                color: archCard.modelData.itemType === "pr_archived"
                    ? Qt.rgba(0.9, 0.5, 0.1, 0.10)
                    : Colours.tPalette.m3surfaceVariant
                opacity: 0.6
            }

            RowLayout {
                id: archInner
                anchors.left: parent.left; anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.normal
                anchors.rightMargin: Tokens.padding.normal
                spacing: Tokens.spacing.small

                // Status chip
                StyledRect {
                    implicitWidth: archChip.implicitWidth + 8
                    implicitHeight: archChip.implicitHeight + 3
                    radius: Tokens.rounding.full
                    color: archCard.modelData.itemType === "pr_archived"
                        ? Colours.palette.m3secondaryContainer
                        : Colours.palette.m3surfaceVariant

                    StyledText {
                        id: archChip; anchors.centerIn: parent
                        text: archCard.modelData.itemType === "pr_archived" ? qsTr("dismissed") : qsTr("merged")
                        font.pixelSize: Tokens.font.sizes.small - 1
                        color: Colours.palette.m3secondary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1

                    StyledText {
                        Layout.fillWidth: true; text: archCard.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: Tokens.font.sizes.small
                        opacity: 0.8
                    }

                    StyledText {
                        text: archCard.modelData.repo + " · " + _fmtAge(archCard.modelData.ageMinutes)
                        font.pixelSize: Tokens.font.sizes.small - 1
                        color: Colours.palette.m3secondary
                        opacity: 0.7
                    }
                }

                // Undismiss button (only for archived/dismissed)
                Item {
                    visible: archCard.modelData.itemType === "pr_archived"
                    implicitWidth: undismissIcon.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: undismissIcon.implicitHeight + Tokens.padding.small

                    MaterialIcon {
                        id: undismissIcon; anchors.centerIn: parent
                        text: "unarchive"; color: Colours.palette.m3secondary
                        font.pixelSize: Tokens.font.sizes.normal
                    }

                    StateLayer {
                        anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.palette.m3onSurface
                        onClicked: GitWatcher.undismiss(archCard.modelData.prId)
                    }
                }
            }

            StateLayer {
                anchors.fill: parent; radius: Tokens.rounding.normal; color: Colours.palette.m3onSurface
                onClicked: Qt.openUrlExternally(archCard.modelData.url)
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _fmtAge(minutes: int): string {
        if (!minutes || minutes < 1) return qsTr("now");
        if (minutes < 60) return qsTr("%1m").arg(minutes);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return m > 0 ? qsTr("%1h%2m").arg(h).arg(m) : qsTr("%1h").arg(h);
    }

    function _fmtTime(iso: string): string {
        if (!iso) return "";
        try { return new Date(iso).toLocaleTimeString(Qt.locale(), Locale.ShortFormat); }
        catch (e) { return iso; }
    }
}
