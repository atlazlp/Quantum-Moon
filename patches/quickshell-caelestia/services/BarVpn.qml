pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Singleton {
    id: root

    readonly property string configPath: Quickshell.env("HOME") + "/.config/caelestia/bar-vpn.json"

    property var vpnData: ({
            "enabled": false,
            "connectionName": "",
            "displayName": ""
        })

    readonly property bool configured: (vpnData?.enabled ?? false) && String(vpnData?.connectionName ?? "").length > 0
    readonly property string connectionName: String(vpnData?.connectionName ?? "")
    readonly property string displayName: {
        const label = String(vpnData?.displayName ?? "");
        return label.length > 0 ? label : connectionName;
    }

    property bool connected: false
    property bool busy: false

    property bool _initialized: false
    property bool _previousConnected: false

    function applyConfig(text: string): void {
        try {
            const parsed = JSON.parse(text);
            root.vpnData = {
                enabled: parsed?.enabled ?? false,
                connectionName: String(parsed?.connectionName ?? ""),
                displayName: String(parsed?.displayName ?? "")
            };
        } catch (e) {
            console.warn("BarVpn: invalid bar-vpn.json:", e);
            root.vpnData = {
                enabled: false,
                connectionName: "",
                displayName: ""
            };
        }
    }

    function refresh(): void {
        if (!configured)
            return;
        statusProc.running = true;
    }

    function toggle(): void {
        if (!configured || busy)
            return;
        busy = true;
        toggleProc.wasConnected = connected;
        toggleProc.command = connected ? ["nmcli", "connection", "down", connectionName] : ["nmcli", "connection", "up", connectionName];
        toggleProc.running = true;
    }

    function emitConnectionToast(connectedNow: bool): void {
        if (GlobalConfig.utilities.toasts.vpnChanged === false)
            return;

        if (connectedNow)
            Toaster.toast(qsTr("VPN connected"), qsTr("%1 is active").arg(displayName), "shield");
        else
            Toaster.toast(qsTr("VPN disconnected"), qsTr("%1 is off").arg(displayName), "shield");
    }

    function onConnectedChanged(): void {
        if (!configured)
            return;

        if (!_initialized) {
            _initialized = true;
            _previousConnected = connected;
            return;
        }

        if (connected === _previousConnected)
            return;

        emitConnectionToast(connected);
        _previousConnected = connected;
    }

    onConnectedChanged: onConnectedChanged()

    onConfiguredChanged: {
        if (configured) {
            refresh();
            return;
        }
        connected = false;
        busy = false;
        _initialized = false;
        _previousConnected = false;
    }

    Component.onCompleted: refresh()

    FileView {
        id: configFile

        path: root.configPath
        watchChanges: true
        printErrors: false

        onLoaded: root.applyConfig(text())
        onFileChanged: reload()
        onLoadFailed: err => {
            if (err !== FileViewError.FileNotFound)
                console.warn("BarVpn: could not load", root.configPath);
            root.vpnData = {
                enabled: false,
                connectionName: "",
                displayName: ""
            };
        }
    }

    Process {
        id: statusProc

        command: ["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(line => line.length > 0);
                root.connected = lines.includes(root.connectionName);
                root.busy = false;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: root.busy = false
        }
    }

    Process {
        id: toggleProc

        property bool wasConnected: false

        onExited: exitCode => {
            root.refresh();
            if (exitCode !== 0 && GlobalConfig.utilities.toasts.vpnChanged !== false) {
                if (!toggleProc.wasConnected)
                    Toaster.toast(qsTr("VPN connection failed"), qsTr("Could not connect to %1").arg(root.displayName), "shield");
                else
                    Toaster.toast(qsTr("VPN disconnect failed"), qsTr("Could not disconnect %1").arg(root.displayName), "shield");
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const err = text.trim();
                if (err.length > 0)
                    console.warn("BarVpn:", err);
            }
        }
    }

    Process {
        running: root.configured
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: root.refresh()
        }
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.configured
        onTriggered: root.refresh()
    }
}
