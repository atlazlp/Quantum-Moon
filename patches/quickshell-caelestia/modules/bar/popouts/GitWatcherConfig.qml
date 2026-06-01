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

    readonly property string _configPath: Quickshell.env("HOME") + "/.config/caelestia/git-watcher.json"
    readonly property string _reposPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher-repos.json"
    readonly property string _pidPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher.pid"

    property var _cfg: ({})
    // [{project: "...", repos: [{id, name}]}]
    property var _projectRepos: []

    implicitWidth: 360
    implicitHeight: Math.min(outerScroll.contentHeight + Tokens.padding.large * 2, 560)

    // -----------------------------------------------------------------------
    // Load config and repos on open
    // -----------------------------------------------------------------------
    FileView {
        id: cfgFile
        path: root._configPath
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
    property string _orgUrl: ""
    property string _project: ""
    property string _identity: ""
    property int _pollInterval: 60
    property int _overdueMinutes: 60
    property bool _notifyNewPr: true
    property bool _notifyComment: true
    property bool _notifyMention: true
    property string _overdueColor: "#ff9500"
    property string _mentionColor: "#e53935"
    // Set of "Project/repoName" strings that are IGNORED (excluded from watching)
    property var _ignoredSet: ({})

    function _syncFormFromCfg(): void {
        _pat = _cfg.pat ?? "";
        _orgUrl = _cfg.organizationUrl ?? "";
        _project = _cfg.project ?? "";
        _identity = _cfg.myIdentity ?? "";
        _pollInterval = _cfg.pollIntervalSeconds ?? 60;
        _overdueMinutes = _cfg.notifications?.overdueMinutes ?? 60;
        _notifyNewPr = _cfg.notifications?.newPr ?? true;
        _notifyComment = _cfg.notifications?.prComment ?? true;
        _notifyMention = _cfg.notifications?.prMention ?? true;
        _overdueColor = _cfg.colors?.overdue ?? "#ff9500";
        _mentionColor = _cfg.colors?.mention ?? "#e53935";
        // Build ignored set from array for fast lookup
        const ignored = _cfg.ignoredRepos ?? [];
        const set = {};
        for (const k of ignored) set[k] = true;
        _ignoredSet = set;
    }

    function _isRepoIgnored(project: string, repoName: string): bool {
        const key = `${project}/${repoName}`;
        return !!(_ignoredSet[key] || _ignoredSet[repoName]);
    }

    function _setRepoIgnored(project: string, repoName: string, ignored: bool): void {
        const key = `${project}/${repoName}`;
        const copy = Object.assign({}, _ignoredSet);
        // Remove both legacy bare-name and qualified forms
        delete copy[repoName];
        if (ignored) {
            copy[key] = true;
        } else {
            delete copy[key];
        }
        _ignoredSet = copy;
    }

    function _buildConfig(): string {
        const cfg = {
            enabled: true,
            pat: _pat,
            organizationUrl: _orgUrl,
            project: _project,
            myIdentity: _identity,
            pollIntervalSeconds: _pollInterval,
            ignoredRepos: Object.keys(_ignoredSet),
            colors: { overdue: _overdueColor, mention: _mentionColor },
            notifications: {
                newPr: _notifyNewPr,
                overdueMinutes: _overdueMinutes,
                prComment: _notifyComment,
                prMention: _notifyMention,
            },
        };
        return JSON.stringify(cfg, null, 2);
    }

    // -----------------------------------------------------------------------
    // Apply
    // -----------------------------------------------------------------------
    Process {
        id: writeProc
        onExited: sighupProc.running = true
    }

    Process {
        id: sighupProc
        command: ["bash", "-c",
            "PID=$(cat " + root._pidPath + " 2>/dev/null) && [ -n \"$PID\" ] && kill -HUP \"$PID\""
        ]
        onExited: root.close()
    }

    function _apply(): void {
        const content = root._buildConfig();
        writeProc.command = [
            "bash", "-c",
            `cat > ${root._configPath} << 'CFGEOF'\n${content}\nCFGEOF\nchmod 600 ${root._configPath}`
        ];
        writeProc.running = true;
    }

    // -----------------------------------------------------------------------
    // UI
    // -----------------------------------------------------------------------
    ScrollView {
        id: outerScroll

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            id: mainLayout

            width: outerScroll.availableWidth
            spacing: Tokens.spacing.normal

            // Header
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
                    implicitWidth: closeBtn.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: closeBtn.implicitHeight + Tokens.padding.small * 2

                    MaterialIcon {
                        id: closeBtn
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3secondary
                    }

                    StateLayer {
                        anchors.fill: parent
                        radius: Tokens.rounding.full
                        color: Colours.palette.m3onSurface
                        onClicked: root.close()
                    }
                }
            }

            // --- Credentials ---
            StyledText { text: qsTr("Credentials"); font.weight: 500 }

            LabeledField {
                label: qsTr("Personal Access Token")
                hint: qsTr("Required scopes: Code (Read), Graph (Read)")
                isPassword: true
                value: root._pat
                onEdited: val => { root._pat = val }
            }

            LabeledField {
                label: qsTr("Organization URL")
                hint: qsTr("https://dev.azure.com/myorg")
                value: root._orgUrl
                onEdited: val => { root._orgUrl = val }
            }

            LabeledField {
                label: qsTr("Default project")
                hint: qsTr("Used for PR URL building (e.g. Cambio)")
                value: root._project
                onEdited: val => { root._project = val }
            }

            LabeledField {
                label: qsTr("My identity (email / UPN)")
                hint: qsTr("For mention and owned PR detection")
                value: root._identity
                onEdited: val => { root._identity = val }
            }

            // --- Polling ---
            StyledText { text: qsTr("Polling"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }

            LabeledField {
                label: qsTr("Poll interval (seconds)")
                hint: qsTr("Minimum 10")
                isNumber: true
                value: root._pollInterval.toString()
                onEdited: val => {
                    const n = parseInt(val);
                    if (!isNaN(n)) root._pollInterval = Math.max(10, n);
                }
            }

            // --- Notifications ---
            StyledText { text: qsTr("Notifications"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }

            SwitchRow {
                label: qsTr("New PR")
                checked: root._notifyNewPr
                onToggled: checked => root._notifyNewPr = checked
            }

            SwitchRow {
                label: qsTr("Comment on my PR")
                checked: root._notifyComment
                onToggled: checked => root._notifyComment = checked
            }

            SwitchRow {
                label: qsTr("Mention (@me)")
                checked: root._notifyMention
                onToggled: checked => root._notifyMention = checked
            }

            LabeledField {
                label: qsTr("Overdue threshold (min)")
                isNumber: true
                value: root._overdueMinutes.toString()
                onEdited: val => {
                    const n = parseInt(val);
                    if (!isNaN(n)) root._overdueMinutes = Math.max(1, n);
                }
            }

            // --- Colors ---
            StyledText { text: qsTr("Colors"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }

            LabeledField {
                label: qsTr("Overdue color")
                hint: "#ff9500"
                value: root._overdueColor
                onEdited: val => root._overdueColor = val
            }

            LabeledField {
                label: qsTr("Mention color")
                hint: "#e53935"
                value: root._mentionColor
                onEdited: val => root._mentionColor = val
            }

            // --- Repositories by project ---
            StyledText {
                text: qsTr("Repositories")
                font.weight: 500
                Layout.topMargin: Tokens.spacing.smaller
            }

            StyledText {
                visible: root._projectRepos.length === 0
                text: qsTr("No repos loaded. Save credentials first, then wait for the first poll.")
                font.pixelSize: Tokens.font.sizes.small
                color: Colours.palette.m3secondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                id: projectRepeater
                model: root._projectRepos

                ProjectSection {
                    id: projSection

                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    projectName: modelData.project
                    repos: modelData.repos
                    ignoredSet: root._ignoredSet

                    onRepoToggled: (proj, repo, ignored) => root._setRepoIgnored(proj, repo, ignored)
                }
            }

            // --- Action buttons ---
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.normal
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
        }
    }

    // -----------------------------------------------------------------------
    // Project collapsible section with per-repo checkboxes
    // -----------------------------------------------------------------------
    component ProjectSection: ColumnLayout {
        id: ps

        required property string projectName
        required property var repos       // [{id, name}]
        required property var ignoredSet  // plain object used as a set

        signal repoToggled(string proj, string repo, bool ignored)

        property bool expanded: false

        spacing: 0

        // Computed: how many repos are enabled
        readonly property int enabledCount: {
            let n = 0;
            for (const r of repos) {
                const key = `${projectName}/${r.name}`;
                if (!ignoredSet[key] && !ignoredSet[r.name]) n++;
            }
            return n;
        }
        // tristate: 0=none, 1=partial, 2=all
        readonly property int checkState: {
            if (enabledCount === 0) return 0;
            if (enabledCount === repos.length) return 2;
            return 1;
        }

        // Header row
        Item {
            Layout.fillWidth: true
            implicitHeight: 44

            // Background on hover
            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.small
                color: Colours.tPalette.m3surfaceVariant
                opacity: 0.6
            }

            RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small
                spacing: Tokens.spacing.small

                // Tristate checkbox icon
                MaterialIcon {
                    text: ps.checkState === 2 ? "check_box"
                        : ps.checkState === 1 ? "indeterminate_check_box"
                        : "check_box_outline_blank"
                    fill: ps.checkState > 0 ? 1 : 0
                    color: ps.checkState === 2 ? Colours.palette.m3primary
                         : ps.checkState === 1 ? Colours.palette.m3secondary
                         : Colours.palette.m3outline

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            // toggle all: if any are enabled, disable all; if none, enable all
                            const disableAll = ps.enabledCount > 0;
                            for (const r of ps.repos)
                                ps.repoToggled(ps.projectName, r.name, disableAll);
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: ps.projectName
                    font.weight: 500
                    elide: Text.ElideRight
                }

                StyledText {
                    text: `${ps.enabledCount}/${ps.repos.length}`
                    font.pixelSize: Tokens.font.sizes.small
                    color: Colours.palette.m3secondary
                }

                MaterialIcon {
                    text: "expand_more"
                    color: Colours.palette.m3secondary
                    rotation: ps.expanded ? 180 : 0

                    Behavior on rotation { Anim { type: Anim.StandardSmall } }
                }

                StateLayer {
                    anchors.fill: parent
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3onSurface
                    onClicked: ps.expanded = !ps.expanded
                }
            }
        }

        // Expandable repo list (scrollable when tall)
        Item {
            id: repoWrapper

            Layout.fillWidth: true
            implicitHeight: ps.expanded ? Math.min(repoCol.implicitHeight, 200) : 0
            clip: true

            Behavior on implicitHeight { Anim {} }

            ScrollView {
                anchors.fill: parent
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    id: repoCol

                    width: repoWrapper.width
                    spacing: 2

                    Repeater {
                        model: ps.repos

                        Item {
                            id: repoRow

                            required property var modelData

                            Layout.fillWidth: true
                            width: parent.width
                            implicitHeight: 36

                            readonly property bool enabled_: {
                                const key = `${ps.projectName}/${modelData.name}`;
                                return !(ps.ignoredSet[key] || ps.ignoredSet[modelData.name]);
                            }

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: Tokens.padding.normal * 2
                                anchors.rightMargin: Tokens.padding.small
                                spacing: Tokens.spacing.small

                                MaterialIcon {
                                    text: repoRow.enabled_ ? "check_box" : "check_box_outline_blank"
                                    fill: repoRow.enabled_ ? 1 : 0
                                    color: repoRow.enabled_ ? Colours.palette.m3primary : Colours.palette.m3outline
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
                                onClicked: ps.repoToggled(ps.projectName, repoRow.modelData.name, repoRow.enabled_)
                            }
                        }
                    }
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Labeled text field inline component
    // -----------------------------------------------------------------------
    component LabeledField: ColumnLayout {
        id: lf

        property string label: ""
        property string hint: ""
        property string value: ""
        property bool isPassword: false
        property bool isNumber: false

        signal edited(string val)

        Layout.fillWidth: true
        spacing: 2

        StyledText {
            text: lf.label
            font.pixelSize: Tokens.font.sizes.small
            color: Colours.palette.m3secondary
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: fieldInput.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.small
            color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

            StyledTextField {
                id: fieldInput

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.small
                anchors.rightMargin: Tokens.padding.small

                text: lf.value
                echoMode: lf.isPassword ? TextField.Password : TextField.Normal
                inputMethodHints: lf.isNumber ? Qt.ImhDigitsOnly : Qt.ImhNone
                placeholderText: lf.hint

                onTextEdited: lf.edited(text)
            }
        }
    }
}
