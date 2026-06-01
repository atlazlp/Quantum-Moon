pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.Internal
import qs.components.misc

Singleton {
    id: root

    readonly property var toplevels: Hyprland.toplevels
    readonly property var workspaces: Hyprland.workspaces
    readonly property var monitors: Hyprland.monitors

    readonly property HyprlandToplevel activeToplevel: {
        const t = Hyprland.activeToplevel;
        if (!t || t.workspace?.name.startsWith("special:"))
            return null;
        return t;
    }
    readonly property HyprlandWorkspace focusedWorkspace: Hyprland.focusedWorkspace
    readonly property HyprlandMonitor focusedMonitor: Hyprland.focusedMonitor
    readonly property int activeWsId: focusedWorkspace?.id ?? 1

    readonly property HyprKeyboard keyboard: extras.devices.keyboards.find(kb => kb.main) ?? null
    readonly property bool capsLock: keyboard?.capsLock ?? false
    readonly property bool numLock: keyboard?.numLock ?? false
    readonly property string defaultKbLayout: keyboard?.layout.split(",")[0] ?? "??"
    readonly property string kbLayoutFull: keyboard?.activeKeymap ?? "Unknown"
    readonly property string kbLayout: kbMap.get(kbLayoutFull) ?? "??"
    readonly property var kbMap: new Map()

    readonly property alias extras: extras
    readonly property alias options: extras.options
    readonly property alias devices: extras.devices

    property bool hadKeyboard

    property var pendingLockWorkspacesRestore: []

    signal configReloaded

    readonly property bool gamePerfMode: extras.options["animations:enabled"] === 0

    property bool _pendingWindowRefresh: false

    Timer {
        id: windowRefreshCoalesce

        interval: 150
        repeat: false

        onTriggered: {
            root._pendingWindowRefresh = false;
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
        }
    }

    function scheduleWindowRefresh(): void {
        if (!root.gamePerfMode) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            return;
        }
        if (!root._pendingWindowRefresh) {
            root._pendingWindowRefresh = true;
            windowRefreshCoalesce.restart();
        }
    }

    function dispatch(request: string): void {
        Hyprland.dispatch(request);
    }

    function wsMonitorName(w: var): string {
        const mon = w.monitor;
        if (typeof mon === "string")
            return mon;
        if (mon !== undefined && mon !== null && mon.name !== undefined && mon.name !== null)
            return mon.name.toString();
        return "";
    }

    function wsWindowCount(w: var): int {
        if (typeof w.windows === "number")
            return w.windows;
        try {
            return w.lastIpcObject?.windows ?? 0;
        } catch (_) {
            return 0;
        }
    }

    function blankWorkspacesForSessionLockPrep(): void {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();

        const monList = [...monitors.values];

        pendingLockWorkspacesRestore = monList.map(m => ({
                "mon": m.name,
                "id": (m.activeWorkspace && typeof m.activeWorkspace.id === "number") ? m.activeWorkspace.id : -1
            }));

        for (const m of monList) {
            const monName = m.name.toString();

            dispatch(`focusmonitor ${monName}`);

            const blanks = workspaces.values.filter(w => wsMonitorName(w) === monName && wsWindowCount(w) === 0).sort((a, b) => {
                try {
                    return a.id - b.id;
                } catch (_) {
                    return 0;
                }
            });

            let dest = blanks[0] ?? null;
            const aid = (m.activeWorkspace && typeof m.activeWorkspace.id === "number") ? m.activeWorkspace.id : null;

            if (dest !== null && typeof dest.id !== "undefined" && aid !== null && dest.id === aid)
                continue;

            if (dest !== null && typeof dest.id !== "undefined")
                dispatch(`workspace ${dest.id}`);
            else
                dispatch(`workspace name:caelestialock_${monName.replace(/[^a-zA-Z0-9_-]/g, "_")}`);
        }

        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    function restoreWorkspacesAfterSessionLock(): void {
        const snap = pendingLockWorkspacesRestore ?? [];
        if (snap.length === 0)
            return;

        for (let i = 0; i < snap.length; i++) {
            const s = snap[i];
            if (typeof s.id !== "number" || s.id < 0)
                continue;
            dispatch(`focusmonitor ${s.mon}`);
            dispatch(`workspace ${s.id}`);
        }
        pendingLockWorkspacesRestore = [];
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
    }

    function cycleSpecialWorkspace(_direction: string): void {}

    function monitorNames(): list<string> {
        return monitors.values.map(e => e.name);
    }

    function monitorFor(screen: ShellScreen): HyprlandMonitor {
        return Hyprland.monitorFor(screen);
    }

    function reloadDynamicConfs(): void {
        extras.batchMessage(["keyword bindlni ,Caps_Lock,global,caelestia:refreshDevices", "keyword bindlni ,Num_Lock,global,caelestia:refreshDevices"]);
    }

    Component.onCompleted: reloadDynamicConfs()

    onCapsLockChanged: {
        if (!GlobalConfig.utilities.toasts.capsLockChanged)
            return;

        if (capsLock)
            Toaster.toast(qsTr("Caps lock enabled"), qsTr("Caps lock is currently enabled"), "keyboard_capslock_badge");
        else
            Toaster.toast(qsTr("Caps lock disabled"), qsTr("Caps lock is currently disabled"), "keyboard_capslock");
    }

    onNumLockChanged: {
        if (!GlobalConfig.utilities.toasts.numLockChanged)
            return;

        if (numLock)
            Toaster.toast(qsTr("Num lock enabled"), qsTr("Num lock is currently enabled"), "looks_one");
        else
            Toaster.toast(qsTr("Num lock disabled"), qsTr("Num lock is currently disabled"), "timer_1");
    }

    onKbLayoutFullChanged: {
        if (hadKeyboard && GlobalConfig.utilities.toasts.kbLayoutChanged)
            Toaster.toast(qsTr("Keyboard layout changed"), qsTr("Layout changed to: %1").arg(kbLayoutFull), "keyboard");

        hadKeyboard = !!keyboard;
    }

    Connections {
        function onRawEvent(event: HyprlandEvent): void {
            const n = event.name;
            if (n.endsWith("v2"))
                return;

            if (n === "configreloaded") {
                root.configReloaded();
                root.reloadDynamicConfs();
            } else if (["workspace", "moveworkspace", "activespecial", "focusedmon"].includes(n)) {
                Hyprland.refreshWorkspaces();
                Hyprland.refreshMonitors();
            } else if (["openwindow", "closewindow", "movewindow"].includes(n)) {
                root.scheduleWindowRefresh();
            } else if (n.includes("mon")) {
                Hyprland.refreshMonitors();
            } else if (n.includes("workspace")) {
                Hyprland.refreshWorkspaces();
            } else if (n.includes("window") || n.includes("group") || ["pin", "fullscreen", "changefloatingmode", "minimize"].includes(n)) {
                Hyprland.refreshToplevels();
            }
        }

        target: Hyprland
    }

    FileView {
        id: kbLayoutFile

        path: Quickshell.env("CAELESTIA_XKB_RULES_PATH") || "/usr/share/X11/xkb/rules/base.lst"
        onLoaded: {
            const layoutMatch = text().match(/! layout\n([\s\S]*?)\n\n/);
            if (layoutMatch) {
                const lines = layoutMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-z]{2,})\s+([a-zA-Z() ]+)$/);
                    if (match)
                        root.kbMap.set(match[2], match[1]);
                }
            }

            const variantMatch = text().match(/! variant\n([\s\S]*?)\n\n/);
            if (variantMatch) {
                const lines = variantMatch[1].split("\n");
                for (const line of lines) {
                    if (!line.trim() || line.trim().startsWith("!"))
                        continue;

                    const match = line.match(/^\s*([a-zA-Z0-9_-]+)\s+([a-z]{2,}): (.+)$/);
                    if (match)
                        root.kbMap.set(match[3], match[2]);
                }
            }
        }
    }

    IpcHandler {
        function refreshDevices(): void {
            extras.refreshDevices();
        }

        function cycleSpecialWorkspace(direction: string): void {
            root.cycleSpecialWorkspace(direction);
        }

        function listSpecialWorkspaces(): string {
            return "";
        }

        target: "hypr"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "refreshDevices"
        description: "Reload devices"
        onPressed: extras.refreshDevices()
        onReleased: extras.refreshDevices()
    }

    HyprExtras {
        id: extras
    }
}
