pragma ComponentBehavior: Bound

import "lock"
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Internal
import qs.services

Scope {
    id: root

    required property Lock lock

    property bool pipewirePlaybackActive: false

    readonly property string audioMarkerPath: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/caelestia-audio-playback.active`

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

    property bool lockedByIdle: false
    property bool manualLock: false
    property bool inIdleLockAction: false

    readonly property var lockedIdleTimeouts: GlobalConfig.general.idle.lockedTimeouts ?? [
        { timeout: 300, idleAction: "dpms off", returnAction: "dpms on" },
        { timeout: 300, idleAction: ["systemctl", "suspend-then-hibernate"] }
    ]

    readonly property bool useLockedTimeouts: root.manualLock && lock.lock.locked

    function handleIdleAction(action: var): void {
        if (!action)
            return;

        if (action === "lock") {
            if (!lock.lock.locked) {
                root.inIdleLockAction = true;
                lock.lock.locked = true;
                root.inIdleLockAction = false;
                root.lockedByIdle = true;
            }
            return;
        }
        if (action === "unlock") {
            lock.lock.locked = false;
            root.lockedByIdle = false;
            root.manualLock = false;
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
            if (!lock.lock.locked) {
                root.lockedByIdle = false;
                root.manualLock = false;
                return;
            }
            if (!root.inIdleLockAction && !root.lockedByIdle)
                root.manualLock = true;
        }
    }

    LogindManager {
        onAboutToSleep: {
            if (GlobalConfig.general.idle.lockBeforeSleep)
                root.lock.lock.locked = true;
        }
        onLockRequested: root.lock.lock.locked = true
        onUnlockRequested: root.lock.lock.unlock()
    }

    Variants {
        model: GlobalConfig.general.idle.timeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && !root.useLockedTimeouts && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }

    Variants {
        model: root.lockedIdleTimeouts

        IdleMonitor {
            required property var modelData

            enabled: root.enabled && root.useLockedTimeouts && (modelData.enabled ?? true)
            timeout: modelData.timeout
            respectInhibitors: modelData.respectInhibitors ?? true
            onIsIdleChanged: root.handleIdleAction(isIdle ? modelData.idleAction : modelData.returnAction)
        }
    }

    readonly property int quantumMoonShuffleTimeout: GlobalConfig.quantumMoon?.shuffleAfter ?? 300

    IdleMonitor {
        enabled: root.enabled && root.quantumMoonShuffleTimeout > 0
        timeout: root.quantumMoonShuffleTimeout
        respectInhibitors: true
        onIsIdleChanged: {
            if (!isIdle && !QuantumMoon.planetLocked)
                QuantumMoon.startInstant();
        }
    }
}
