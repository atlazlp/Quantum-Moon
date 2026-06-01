pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    // -----------------------------------------------------------------------
    // Public state (read by UI)
    // -----------------------------------------------------------------------
    property var prs: []
    property var commentItems: []
    property var mentionItems: []
    property int overdueCount: 0
    property int mentionCount: 0
    property bool loading: false
    property string lastError: ""
    property string lastUpdated: ""

    readonly property bool configured: {
        const d = _configData;
        return d !== null && typeof d === "object" &&
               typeof d.pat === "string" && d.pat.length > 0 &&
               typeof d.organizationUrl === "string" && d.organizationUrl.length > 0;
    }

    // Active when not in game mode and user hasn't hidden it in settings
    readonly property bool active: !GameMode.enabled &&
                                   (GlobalConfig.bar?.status?.showGitWatcher !== false)

    // -----------------------------------------------------------------------
    // Private state
    // -----------------------------------------------------------------------
    property var _configData: null

    readonly property string _configPath: Quickshell.env("HOME") + "/.config/caelestia/git-watcher.json"
    readonly property string _statePath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher-state.json"
    readonly property string _pidPath: Quickshell.env("HOME") + "/.local/state/caelestia/git-watcher.pid"
    readonly property string _daemonPath: Paths.config + "/../caelestia/scripts/git-watcher.py"

    // -----------------------------------------------------------------------
    // Config file watcher
    // -----------------------------------------------------------------------
    FileView {
        id: configFile

        path: root._configPath
        watchChanges: true
        printErrors: false

        onLoaded: {
            try {
                root._configData = JSON.parse(text());
            } catch (e) {
                console.warn("GitWatcher: failed to parse config:", e);
                root._configData = null;
            }
        }
        onFileChanged: reload()
        onLoadFailed: err => {
            console.warn("GitWatcher: config load failed:", err);
            root._configData = null;
        }

        Component.onCompleted: reload()
    }

    // -----------------------------------------------------------------------
    // State file watcher — updates UI when daemon writes new data
    // -----------------------------------------------------------------------
    FileView {
        id: stateFile

        path: root._statePath
        watchChanges: true
        printErrors: false

        onLoaded: root._applyState(text())
        onFileChanged: reload()
    }

    function _applyState(text: string): void {
        try {
            const s = JSON.parse(text);
            root.prs = s.prs ?? [];
            root.commentItems = s.commentItems ?? [];
            root.mentionItems = s.mentionItems ?? [];
            root.overdueCount = s.overdueCount ?? 0;
            root.mentionCount = s.mentionCount ?? 0;
            root.lastError = s.error ?? "";
            root.lastUpdated = s.lastUpdated ?? "";
            root.loading = false;
        } catch (e) {
            root.lastError = "Failed to parse state";
        }
    }

    // -----------------------------------------------------------------------
    // Daemon process (long-running, one instance)
    // -----------------------------------------------------------------------
    readonly property bool _daemonShouldRun: active && configured

    Process {
        id: daemon

        command: ["python3", root._daemonPath]
        running: root._daemonShouldRun

        onExited: exitCode => {
            if (root._daemonShouldRun)
                restartTimer.start();
        }
    }

    Timer {
        id: restartTimer

        interval: 5000
        repeat: false
        onTriggered: {
            if (root._daemonShouldRun && !daemon.running)
                daemon.running = true;
        }
    }

    // -----------------------------------------------------------------------
    // Manual refresh — send SIGHUP to daemon
    // -----------------------------------------------------------------------
    function refresh(): void {
        loading = true;
        sighupProc.running = true;
    }

    Process {
        id: sighupProc

        command: ["bash", "-c",
            "PID=$(cat " + root._pidPath + " 2>/dev/null) && [ -n \"$PID\" ] && kill -HUP \"$PID\""
        ]
        onExited: loadingFallback.restart()
    }

    Timer {
        id: loadingFallback
        interval: 8000
        repeat: false
        onTriggered: root.loading = false
    }

    // -----------------------------------------------------------------------
    // Apply config from the settings modal.
    // Lives in the singleton (always alive) so close() in the modal can be
    // called immediately — no async dependency that would leave the overlay stuck.
    // -----------------------------------------------------------------------
    function applyConfig(jsonText: string): void {
        applyWriteProc.pendingJson = jsonText;
        applyWriteProc.running = true;
    }

    Process {
        id: applyWriteProc

        property string pendingJson: ""

        // Pass JSON as a direct argv element — no shell quoting issues
        command: [
            "python3", "-c",
            "import sys, os; open(sys.argv[1],'w').write(sys.argv[2]); os.chmod(sys.argv[1], 0o600)",
            root._configPath,
            applyWriteProc.pendingJson
        ]
        onExited: applySighupProc.running = true
    }

    Process {
        id: applySighupProc

        command: ["bash", "-c",
            "PID=$(cat " + root._pidPath + " 2>/dev/null) && [ -n \"$PID\" ] && kill -HUP \"$PID\""
        ]
    }
}
