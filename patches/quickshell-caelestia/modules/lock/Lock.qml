pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils

Scope {
    property alias lock: lock

    readonly property string lockedSleepScript: `${Paths.config}/scripts/locked-sleep-after.sh`
    readonly property int lockedSleepAfter: GlobalConfig.general.idle?.lockedSleepAfter ?? 300

    WlSessionLock {
        id: lock

        signal unlock

        onUnlock: disarmLockedSleep()

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    Pam {
        id: pam

        lock: lock
    }

    function dismissSessionDrawer(): void {
        const visibilities = Visibilities.getForActive();
        if (!visibilities)
            return;
        visibilities.session = false;
    }

    function armLockedSleep(): void {
        Quickshell.execDetached(["bash", lockedSleepScript, "arm", String(lockedSleepAfter)]);
    }

    function disarmLockedSleep(): void {
        Quickshell.execDetached(["bash", lockedSleepScript, "disarm"]);
    }

    function sessionLock(): void {
        dismissSessionDrawer();
        lock.locked = true;
        armLockedSleep();
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "lock"
        description: "Lock the current session"
        onPressed: sessionLock()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "unlock"
        description: "Unlock the current session"
        onPressed: lock.unlock()
    }

    IpcHandler {
        function lock(): void {
            sessionLock();
        }

        function unlock(): void {
            lock.unlock();
        }

        function isLocked(): bool {
            return lock.locked;
        }

        target: "lock"
    }
}
