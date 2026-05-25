pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Internal
import qs.services
import qs.utils

Scope {
    id: root

    required property Lock lock

    property bool pipewirePlaybackActive: false

    readonly property string audioMarkerPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/caelestia-audio-playback.active`
    readonly property string lockedSleepScript: `${Paths.config}/scripts/locked-sleep-after.sh`
    readonly property int lockedSleepAfter: GlobalConfig.general.idle.lockedSleepAfter ?? 300

    FileView {
        id: audioMarker

        printErrors: false
        path: root.audioMarkerPath
        onLoaded: root.pipewirePlaybackActive = true
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound)
                root.pipewirePlaybackActive = false;
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: GlobalConfig.general.idle.inhibitWhenAudio
        onTriggered: audioMarker.reload()
    }

    readonly property bool enabled: !(GlobalConfig.general.idle.inhibitWhenAudio && (Players.list.some(p => p.isPlaying) || root.pipewirePlaybackActive))

    function armLockedSleep(): void {
        if (!root.enabled)
            return;
        Quickshell.execDetached(["bash", root.lockedSleepScript, "arm", String(root.lockedSleepAfter)]);
    }

    function disarmLockedSleep(): void {
        Quickshell.execDetached(["bash", root.lockedSleepScript, "disarm"]);
    }

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock") {
            lock.sessionLock();
            return;
        }
        if (action === "unlock") {
            root.disarmLockedSleep();
            lock.lock.locked = false;
            return;
        }
        if (typeof action === "string")
            Hypr.dispatch(action);
        else
            Quickshell.execDetached(action);
    }

    Connections {
        target: lock.lock

        function onLockedChanged(): void {
            if (!lock.lock.locked)
                Hypr.dispatch("dpms on");
        }
    }

    LogindManager {
        onAboutToSleep: {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }
        onLockRequested: lock.sessionLock()
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && !lock.lock.locked && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }
}
