pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.launcher.services
import qs.services

Singleton {
    id: root

    readonly property string windowMenuPy: Quickshell.env("HOME") + "/.config/caelestia/scripts/window_menu.py"
    readonly property var openLabel: /^(view|open|show|reveal|ver|abrir|mostrar)$/i

    function isOpenAction(action): bool {
        return root.openLabel.test((action?.text ?? "").trim());
    }

    function filteredActions(actions): list<var> {
        return (actions ?? []).filter(a => !isOpenAction(a));
    }

    function hintPid(hints): int {
        if (!hints)
            return 0;
        const raw = hints["sender-pid"] ?? hints.senderPid;
        if (raw === undefined || raw === null)
            return 0;
        const pid = typeof raw === "number" ? raw : parseInt(raw, 10);
        return Number.isFinite(pid) && pid > 0 ? pid : 0;
    }

    function focus(notifData, dismissPopup): void {
        const n = notifData?.notification;
        focusProc.summary = notifData?.summary ?? "";
        focusProc.body = notifData?.body ?? "";
        focusProc.appName = notifData?.appName ?? "";
        focusProc.desktopEntry = n?.desktopEntry ?? "";
        focusProc.pid = hintPid(notifData?.hints);
        focusProc.dismissPopup = dismissPopup === true;
        focusProc.notifData = notifData;
        focusProc.running = true;
    }

    Process {
        id: focusProc

        property string summary: ""
        property string body: ""
        property string appName: ""
        property string desktopEntry: ""
        property int pid: 0
        property bool dismissPopup: false
        property var notifData: null

        command: [
            "python3",
            root.windowMenuPy,
            "focus-notif",
            "--pid", pid.toString(),
            "--desktop", desktopEntry,
            "--app", appName,
            "--summary", summary,
            "--body", body
        ]
        onExited: (exitCode, _status) => {
            if (exitCode !== 0) {
                const desktopId = desktopEntry;
                const entry = desktopId.length > 0 ? DesktopEntries.applications.values.find(e => e.id === desktopId || e.id === `${desktopId}.desktop`) : DesktopEntries.heuristicLookup(appName);
                if (entry)
                    Apps.launch(entry);
            }

            if (dismissPopup && notifData?.popup)
                notifData.popup = false;
        }
    }
}
