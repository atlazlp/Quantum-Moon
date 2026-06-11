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
    readonly property string resumeGracePath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/caelestia-resume-grace.until`
    readonly property string lockedSleepScript: `${Paths.config}/scripts/locked-sleep-after.sh`
    readonly property int lockedSleepAfter: GlobalConfig.general.idle.lockedSleepAfter ?? 300

    FileView {
        id: resumeGrace

        printErrors: false
        path: root.resumeGracePath
    }

    function withinResumeGrace(): bool {
        if (!resumeGrace.loaded)
            return false;
        const until = parseInt(resumeGrace.text(), 10);
        if (Number.isNaN(until) || until <= 0)
            return false;
        return Math.floor(Date.now() / 1000) < until;
    }

    function actionIsSuspend(action: var): bool {
        if (typeof action === "string")
            return /suspend/i.test(action);
        if (Array.isArray(action))
            return action.some(part => typeof part === "string" && /suspend/i.test(part));
        return false;
    }

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
        running: true
        onTriggered: {
            if (GlobalConfig.general.idle.inhibitWhenAudio)
                audioMarker.reload();
            resumeGrace.reload();
        }
    }

    readonly property bool enabled: !(GlobalConfig.general.idle.inhibitWhenAudio && (Players.list.some(p => p.isPlaying) || root.pipewirePlaybackActive))
    readonly property bool shuffleOnIdle: GlobalConfig.quantumMoon?.shuffleOnIdle !== false

    function idleActionNeedsShuffle(action: var): bool {
        if (!root.shuffleOnIdle || !root.enabled || QuantumMoon.planetLocked)
            return false;
        if (action === "lock")
            return true;
        if (typeof action === "string" && /dpms\s+off/i.test(action))
            return true;
        return false;
    }

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
        if (root.withinResumeGrace() && root.actionIsSuspend(action))
            return;
        if (root.idleActionNeedsShuffle(action)) {
            QuantumMoon.startInstantThen(() => root.runIdleAction(action));
            return;
        }
        root.runIdleAction(action);
    }

    function runIdleAction(action: var): void {
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
