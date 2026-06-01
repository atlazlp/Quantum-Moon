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
    property var _availableRepos: []
    property bool _dirty: false

    implicitWidth: 340
    implicitHeight: mainLayout.implicitHeight + Tokens.padding.large * 2

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
        onLoadFailed: root._cfg = {}
    }

    FileView {
        id: reposFile
        path: root._reposPath
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                root._availableRepos = JSON.parse(text());
            } catch (e) {
                root._availableRepos = [];
            }
        }
    }

    Component.onCompleted: {
        cfgFile.reload();
        reposFile.reload();
    }

    // -----------------------------------------------------------------------
    // Form state (local copies, written on Apply)
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
    property var _ignoredRepos: []

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
        _ignoredRepos = _cfg.ignoredRepos ?? [];
    }

    function _buildConfig(): string {
        const cfg = {
            enabled: true,
            pat: _pat,
            organizationUrl: _orgUrl,
            project: _project,
            myIdentity: _identity,
            pollIntervalSeconds: _pollInterval,
            ignoredRepos: _ignoredRepos,
            colors: {
                overdue: _overdueColor,
                mention: _mentionColor,
            },
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
    // Apply — write config and SIGHUP the daemon
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
        // Write via a bash heredoc so we don't need a write API
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
        anchors.fill: parent
        contentWidth: parent.width

        ColumnLayout {
            id: mainLayout

            width: root.width - Tokens.padding.large * 2
            x: Tokens.padding.large
            y: Tokens.padding.large
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

                StateLayer {
                    implicitWidth: closeIcon.implicitWidth + Tokens.padding.small * 2
                    implicitHeight: closeIcon.implicitHeight + Tokens.padding.small * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3onSurface
                    onClicked: root.close()

                    MaterialIcon {
                        id: closeIcon
                        anchors.centerIn: parent
                        text: "close"
                        color: Colours.palette.m3secondary
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
                hint: qsTr("e.g. https://dev.azure.com/myorg")
                value: root._orgUrl
                onEdited: val => { root._orgUrl = val }
            }

            LabeledField {
                label: qsTr("Project")
                hint: qsTr("e.g. Cambio")
                value: root._project
                onEdited: val => { root._project = val }
            }

            LabeledField {
                label: qsTr("My identity (email / UPN)")
                hint: qsTr("Used to detect mentions and owned PRs")
                value: root._identity
                onEdited: val => { root._identity = val }
            }

            // --- Poll interval ---
            StyledText { text: qsTr("Polling"); font.weight: 500; Layout.topMargin: Tokens.spacing.smaller }

            LabeledField {
                label: qsTr("Poll interval (seconds)")
                hint: qsTr("How often to check for new PRs (minimum 10)")
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
                label: qsTr("Overdue threshold (minutes)")
                hint: qsTr("PRs older than this trigger a persistent notification")
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
                hint: qsTr("CSS hex color, e.g. #ff9500")
                value: root._overdueColor
                onEdited: val => root._overdueColor = val
            }

            LabeledField {
                label: qsTr("Mention color")
                hint: qsTr("CSS hex color, e.g. #e53935")
                value: root._mentionColor
                onEdited: val => root._mentionColor = val
            }

            // --- Repos ---
            StyledText {
                text: qsTr("Repositories")
                font.weight: 500
                Layout.topMargin: Tokens.spacing.smaller
            }

            StyledText {
                visible: root._availableRepos.length === 0
                text: qsTr("No repos loaded yet. Save credentials and wait for the first poll.")
                font.pixelSize: Tokens.font.sizes.small
                color: Colours.palette.m3secondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: root._availableRepos

                SwitchRow {
                    id: repoRow

                    required property var modelData

                    label: modelData.name
                    checked: !root._ignoredRepos.includes(modelData.name)
                    onToggled: checked => {
                        const list = [...root._ignoredRepos];
                        const idx = list.indexOf(modelData.name);
                        if (!checked && idx === -1)
                            list.push(modelData.name);
                        else if (checked && idx !== -1)
                            list.splice(idx, 1);
                        root._ignoredRepos = list;
                    }
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
    // Internal labeled text field component
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
