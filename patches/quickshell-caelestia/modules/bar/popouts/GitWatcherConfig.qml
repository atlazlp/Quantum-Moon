pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    signal close()

    readonly property string _reposPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher-repos.json"

    property var _cfg: ({})
    // [{project: "...", repos: [{id, name}]}]
    property var _projectRepos: []

    implicitWidth: 480
    implicitHeight: Math.min(formScroll.contentHeight + Tokens.padding.large * 2 + actionBar.implicitHeight + Tokens.spacing.normal, 580)

    // -----------------------------------------------------------------------
    // Load config and repos on open
    // -----------------------------------------------------------------------
    FileView {
        id: cfgFile
        path: GitWatcher._configPath
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root._cfg = JSON.parse(text());
            } catch (e) {
                root._cfg = {};
            }
            root._syncFormFromCfg();
        }
    }

    FileView {
        id: reposFile
        path: root._reposPath
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root._projectRepos = JSON.parse(text());
            } catch (e) {
                root._projectRepos = [];
            }
        }
    }

    Component.onCompleted: {
        cfgFile.reload();
        reposFile.reload();
    }

    // -----------------------------------------------------------------------
    // Form state
    // -----------------------------------------------------------------------
    property string _pat: ""
    property bool   _patVisible: false
    property string _orgUrl: ""
    property string _identity: ""
    property int    _pollInterval: 60
    property int    _overdueMinutes: 60
    property bool   _notifyNewPr: true
    property bool   _notifyComment: true
    property bool   _notifyMention: true
    property string _overdueColor: "#ff9500"
    property string _mentionColor: "#e53935"
    // "Project/repoName" → true   (allowlist of repos to watch)
    property var    _watchedSet: ({})

    function _syncFormFromCfg(): void {
        _pat          = _cfg.pat ?? "";
        _orgUrl       = _cfg.organizationUrl ?? "";
        _identity     = _cfg.myIdentity ?? "";
        _pollInterval = _cfg.pollIntervalSeconds ?? 60;
        _overdueMinutes = _cfg.notifications?.overdueMinutes ?? 60;
        _notifyNewPr    = _cfg.notifications?.newPr ?? true;
        _notifyComment  = _cfg.notifications?.prComment ?? true;
        _notifyMention  = _cfg.notifications?.prMention ?? true;
        _overdueColor   = _cfg.colors?.overdue ?? "#ff9500";
        _mentionColor   = _cfg.colors?.mention ?? "#e53935";

        // Build watched set from new watchedRepos field.
        // If config still has old ignoredRepos, migrate: treat everything NOT in
        // ignoredRepos as watched (if ignoredRepos is empty, default-off = empty).
        const set = {};
        if (_cfg.watchedRepos) {
            for (const k of _cfg.watchedRepos) set[k] = true;
        }
        // Old ignoredRepos with entries → treat non-ignored repos as watched
        // (only applies when migrating from the denylist format)
        // If both absent or ignoredRepos empty → default off, start empty.
        _watchedSet = set;
    }

    function _isRepoWatched(project: string, repo: string): bool {
        const key = `${project}/${repo}`;
        return !!(_watchedSet[key] || _watchedSet[repo]);
    }

    function _setRepoWatched(project: string, repo: string, watch: bool): void {
        const key = `${project}/${repo}`;
        const copy = Object.assign({}, _watchedSet);
        delete copy[repo]; // remove legacy bare-name if present
        if (watch) copy[key] = true; else delete copy[key];
        _watchedSet = copy;
    }

    function _buildConfig(): string {
        return JSON.stringify({
            enabled: true,
            pat: _pat,
            organizationUrl: _orgUrl,
            myIdentity: _identity,
            pollIntervalSeconds: _pollInterval,
            watchedRepos: Object.keys(_watchedSet),
            colors: { overdue: _overdueColor, mention: _mentionColor },
            notifications: {
                newPr: _notifyNewPr,
                overdueMinutes: _overdueMinutes,
                prComment: _notifyComment,
                prMention: _notifyMention,
            },
        }, null, 2);
    }

    // -----------------------------------------------------------------------
    // Apply — delegates to GitWatcher service (always-alive singleton),
    // then closes immediately so the overlay doesn't get stuck.
    // -----------------------------------------------------------------------
    function _apply(): void {
        GitWatcher.applyConfig(root._buildConfig());
        root.close();
    }

    // -----------------------------------------------------------------------
    // Layout: scrollable form + fixed action bar
    // -----------------------------------------------------------------------
    ScrollView {
        id: formScroll

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionBar.top
        anchors.margins: Tokens.padding.large
        anchors.bottomMargin: Tokens.spacing.normal
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: formLayout

            width: formScroll.availableWidth
            spacing: Tokens.spacing.normal

            // ── Header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon { text: "settings"; fill: 1; color: Colours.palette.m3secondary }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("GitWatcher Config")
                    font.weight: 600
                }

                Item {
                    implicitWidth: 32; implicitHeight: 32
                    MaterialIcon { anchors.centerIn: parent; text: "close"; color: Colours.palette.m3secondary }
                    StateLayer { anchors.fill: parent; radius: Tokens.rounding.full; color: Colours.palette.m3onSurface; onClicked: root.close() }
                }
            }

            // ── Credentials ──
            StyledText { text: qsTr("Credentials"); font.weight: 500 }

            // PAT with visibility toggle
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText { text: qsTr("Personal Access Token"); font.pixelSize: Tokens.font.sizes.small; color: Colours.palette.m3secondary }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: patField.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.small
                    color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.small
                        anchors.rightMargin: 2
                        spacing: 0

                        StyledTextField {
                            id: patField
                            Layout.fillWidth: true
                            text: root._pat
                            echoMode: root._patVisible ? TextField.Normal : TextField.Password
                            placeholderText: qsTr("Required scopes: Code (Read), Graph (Read)")
                            onTextEdited: root._pat = text
                        }

                        Item {
                            implicitWidth: 28; implicitHeight: 28
                            MaterialIcon { anchors.centerIn: parent; text: root._patVisible ? "visibility_off" : "visibility"; color: Colours.palette.m3secondary; font.pixelSize: Tokens.font.sizes.normal }
                            StateLayer { anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.palette.m3onSurface; onClicked: root._patVisible = !root._patVisible }
                        }
                    }
                }
            }

            LabeledField { label: qsTr("Organization URL"); hint: "https://dev.azure.com/myorg"; value: root._orgUrl; onEdited: val => root._orgUrl = val }
            LabeledField { label: qsTr("My identity (email / UPN)"); hint: qsTr("For mention and owned PR detection"); value: root._identity; onEdited: val => root._identity = val }

            // ── Polling ──
            StyledText { text: qsTr("Polling"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }
            LabeledField { label: qsTr("Poll interval (seconds)"); hint: qsTr("Minimum 10"); isNumber: true; value: root._pollInterval.toString(); onEdited: val => { const n = parseInt(val); if (!isNaN(n)) root._pollInterval = Math.max(10, n); } }

            // ── Notifications ──
            StyledText { text: qsTr("Notifications"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }
            SwitchRow { label: qsTr("New PR"); checked: root._notifyNewPr; onToggled: c => root._notifyNewPr = c }
            SwitchRow { label: qsTr("Comment on my PR"); checked: root._notifyComment; onToggled: c => root._notifyComment = c }
            SwitchRow { label: qsTr("Mention (@me)"); checked: root._notifyMention; onToggled: c => root._notifyMention = c }
            LabeledField { label: qsTr("Overdue threshold (min)"); hint: qsTr("Stalled + unapproved after this long"); isNumber: true; value: root._overdueMinutes.toString(); onEdited: val => { const n = parseInt(val); if (!isNaN(n)) root._overdueMinutes = Math.max(1, n); } }

            // ── Colors ──
            StyledText { text: qsTr("Colors"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }
            LabeledField { label: qsTr("Overdue color"); hint: "#ff9500"; value: root._overdueColor; onEdited: val => root._overdueColor = val }
            LabeledField { label: qsTr("Mention color"); hint: "#e53935"; value: root._mentionColor; onEdited: val => root._mentionColor = val }

            // ── Repositories ──
            StyledText { text: qsTr("Repositories"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }

            StyledText {
                visible: root._projectRepos.length === 0
                text: qsTr("No repos loaded yet — save credentials first and wait for a poll.")
                font.pixelSize: Tokens.font.sizes.small
                color: Colours.palette.m3secondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: root._projectRepos

                ProjectSection {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    projectName: modelData.project
                    repos: modelData.repos ?? []
                    watchedSet: root._watchedSet

                    onRepoToggled: (proj, repo, watch) => root._setRepoWatched(proj, repo, watch)
                }
            }
        }
    }

    // Fixed action bar
    RowLayout {
        id: actionBar

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        anchors.bottomMargin: Tokens.padding.large
        spacing: Tokens.spacing.small

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Cancel")
            icon: "close"
            inactiveColour: Colours.palette.m3surfaceVariant
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            verticalPadding: Tokens.padding.small
            onClicked: root.close()
        }

        IconTextButton {
            Layout.fillWidth: true
            text: qsTr("Apply")
            icon: "check"
            inactiveColour: Colours.palette.m3primaryContainer
            inactiveOnColour: Colours.palette.m3onPrimaryContainer
            verticalPadding: Tokens.padding.small
            onClicked: root._apply()
        }
    }

    // -----------------------------------------------------------------------
    // Project section component
    // -----------------------------------------------------------------------
    component ProjectSection: ColumnLayout {
        id: ps

        required property string projectName
        required property var    repos
        required property var    watchedSet

        signal repoToggled(string proj, string repo, bool watch)

        property bool expanded: false
        property string _name: ""
        property var    _repos: []
        Component.onCompleted: { _name = projectName; _repos = repos; }

        readonly property int watchedCount: {
            let n = 0;
            for (const r of _repos) {
                const key = `${_name}/${r.name}`;
                if (watchedSet[key] || watchedSet[r.name]) n++;
            }
            return n;
        }
        // 0=none 1=partial 2=all
        readonly property int checkState: {
            if (_repos.length === 0) return 0;
            if (watchedCount === 0) return 0;
            if (watchedCount === _repos.length) return 2;
            return 1;
        }

        spacing: 0
        clip: false

        // Header
        Item {
            Layout.fillWidth: true
            implicitHeight: 44

            StyledRect { anchors.fill: parent; radius: Tokens.rounding.small; color: Colours.tPalette.m3surfaceVariant; opacity: 0.5 }

            // Checkbox (z:2 — separate from expand StateLayer)
            Item {
                id: checkboxHit
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: parent.height
                z: 2

                MaterialIcon {
                    anchors.centerIn: parent
                    fill: ps.checkState > 0 ? 1 : 0
                    text: ps.checkState === 2 ? "check_box"
                        : ps.checkState === 1 ? "indeterminate_check_box"
                        : "check_box_outline_blank"
                    color: ps.checkState === 2 ? Colours.palette.m3primary
                         : ps.checkState === 1 ? Colours.palette.m3secondary
                         : Colours.palette.m3outline
                    font.pixelSize: Tokens.font.sizes.large
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const enable = ps.watchedCount === 0;
                        for (const r of ps._repos)
                            ps.repoToggled(ps._name, r.name, enable);
                    }
                }
            }

            // Expand trigger
            Item {
                anchors.left: checkboxHit.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: ps._name
                        font.weight: 500
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: `${ps.watchedCount}/${ps._repos.length}`
                        font.pixelSize: Tokens.font.sizes.small
                        color: Colours.palette.m3secondary
                    }

                    MaterialIcon {
                        text: "expand_more"
                        color: Colours.palette.m3secondary
                        rotation: ps.expanded ? 180 : 0
                        Behavior on rotation { Anim { type: Anim.StandardSmall } }
                    }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3onSurface
                    onClicked: ps.expanded = !ps.expanded
                }
            }
        }

        // Repo list
        Item {
            id: repoWrapper
            Layout.fillWidth: true
            implicitHeight: ps.expanded ? Math.min(repoScrollView.contentHeight + 4, 200) : 0
            clip: true
            Behavior on implicitHeight { Anim {} }

            ScrollView {
                id: repoScrollView
                anchors.fill: parent
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: repoCol
                    width: repoScrollView.availableWidth
                    spacing: 0

                    Repeater {
                        model: ps._repos

                        Item {
                            id: repoRow
                            required property var modelData
                            width: repoCol.width
                            implicitHeight: 36

                            readonly property bool _watched: {
                                const key = `${ps._name}/${modelData.name}`;
                                return !!(ps.watchedSet[key] || ps.watchedSet[modelData.name]);
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.padding.normal * 2 + 4
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    fill: repoRow._watched ? 1 : 0
                                    text: repoRow._watched ? "check_box" : "check_box_outline_blank"
                                    color: repoRow._watched ? Colours.palette.m3primary : Colours.palette.m3outline
                                    font.pixelSize: Tokens.font.sizes.normal
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: repoRow.modelData.name
                                    font.pixelSize: Tokens.font.sizes.small
                                    elide: Text.ElideRight
                                }
                            }

                            StateLayer {
                                anchors.fill: parent
                                radius: Tokens.rounding.small
                                color: Colours.palette.m3onSurface
                                onClicked: ps.repoToggled(ps._name, repoRow.modelData.name, !repoRow._watched)
                            }
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Labeled field helper
    // -----------------------------------------------------------------------
    component LabeledField: ColumnLayout {
        id: lf

        property string label: ""
        property string hint: ""
        property string value: ""
        property bool isNumber: false

        signal edited(string val)

        Layout.fillWidth: true
        spacing: 2

        StyledText { text: lf.label; font.pixelSize: Tokens.font.sizes.small; color: Colours.palette.m3secondary }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: fieldTf.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.small
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

            StyledTextField {
                id: fieldTf
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                text: lf.value
                inputMethodHints: lf.isNumber ? Qt.ImhDigitsOnly : Qt.ImhNone
                placeholderText: lf.hint
                onTextEdited: lf.edited(text)
            }
        }
    }
}
