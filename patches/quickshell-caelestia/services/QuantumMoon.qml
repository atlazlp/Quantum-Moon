pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property real overlayOpacity: 0
    property bool active: false
    property bool planetLocked: false
    property string lockedSlug: ""
    property real lockMarkerX: -1
    property real lockMarkerY: -1
    property bool _lockStateHydrated: false
    property bool _applyingLockFromDisk: false
    property bool _lockSlugMissing: false
    property bool _pendingLockMarkerRoll: false
    property bool _ignoreLockStateFileOnce: false
    property string pendingApplySlug: ""
    property var _requestQueue: []
    property string _pickResolvedSlug: ""
    property var _instantDoneCallback: null

    readonly property var wheelPlanetSlugs: ["brittle-hollow", "dark-bramble", "giants-deep", "hourglass-twins", "timber-hearth"]
    readonly property int wheelZeroPlanetIndex: 2
    readonly property real wheelDegPerPlanetIndex: 46.5
    readonly property real wheelRotationOffsetDeg: 0.5
    readonly property int wheelSpinDurationMs: 500
    readonly property int wheelSpinLeadMs: root.wheelSpinDurationMs + 24

    property real wheelRingDisplayDeg: 0.5

    NumberAnimation {
        id: wheelRingSpin

        target: root
        property: "wheelRingDisplayDeg"
        duration: root.wheelSpinDurationMs
        easing.type: Easing.InOutQuint
    }

    readonly property bool wheelRingSpinning: wheelRingSpin.running

    readonly property string lockStateFile: Paths.home + "/.local/state/quantum-moon/state.json"

    readonly property real lockMarkerBarHeight: 40
    readonly property real lockMarkerBarWidth: lockMarkerBarHeight * 16 / 9
    readonly property real lockMarkerThumbSize: 30
    readonly property real lockMarkerSize: 6
    readonly property real lockMarkerThumbClearancePad: 0.5

    function isLockMarkerInsideBarBounds(x: real, y: real, barWidth: real, barHeight: real): bool {
        if (x < 0 || y < 0)
            return false;
        if (x + root.lockMarkerSize > barWidth + 0.5 || y + root.lockMarkerSize > barHeight + 0.5)
            return false;
        return true;
    }

    function lockMarkerOverlapsThumb(x: real, y: real, barWidth: real, barHeight: real): bool {
        const cx = barWidth * 0.5;
        const cy = barHeight * 0.5;
        const clearance = root.lockMarkerThumbSize * 0.5 + root.lockMarkerSize * 0.5 + root.lockMarkerThumbClearancePad;
        const s = root.lockMarkerSize;
        return x < cx + clearance && x + s > cx - clearance && y < cy + clearance && y + s > cy - clearance;
    }

    function isLockMarkerPlacementValid(x: real, y: real, barWidth: real, barHeight: real): bool {
        return root.isLockMarkerInsideBarBounds(x, y, barWidth, barHeight)
            && !root.lockMarkerOverlapsThumb(x, y, barWidth, barHeight);
    }

    function randomLockMarkerOffset(barWidth: real, barHeight: real): point {
        const s = root.lockMarkerSize;
        const bw = barWidth - s;
        const bh = barHeight - s;
        if (bw <= 0 || bh <= 0)
            return Qt.point(0, 0);
        const cx = barWidth * 0.5;
        const cy = barHeight * 0.5;
        const clearance = root.lockMarkerThumbSize * 0.5 + root.lockMarkerSize * 0.5 + root.lockMarkerThumbClearancePad;
        const pad = 2;
        const edgeGap = 1;
        const leftMax = cx - clearance - s - edgeGap;
        const rightMin = cx + clearance + edgeGap;
        const vertHalfSpan = Math.min(root.lockMarkerThumbSize * 0.55, bh * 0.42);

        function clampPick(px: real, py: real): point {
            const x = Math.max(0, Math.min(px, bw));
            const y = Math.max(0, Math.min(py, bh));
            if (root.isLockMarkerPlacementValid(x, y, barWidth, barHeight))
                return Qt.point(x, y);
            return Qt.point(-1, -1);
        }

        for (let i = 0; i < 140; i++) {
            const pickLeft = Math.random() < 0.5;
            let x = -1;
            if (pickLeft) {
                if (leftMax > pad) {
                    const span = leftMax - pad;
                    x = leftMax - Math.random() * Math.random() * span;
                }
            } else if (rightMin < bw) {
                const span = bw - rightMin;
                x = rightMin + Math.random() * Math.random() * span;
            }
            if (x < 0)
                continue;
            const jy = (Math.random() * 2 - 1) * vertHalfSpan;
            const y = cy - s * 0.5 + jy;
            const pt = clampPick(x, y);
            if (pt.x >= 0)
                return pt;
        }

        const steps = 11;
        for (let si = 0; si < steps; si++) {
            const t = steps === 1 ? 0.5 : si / (steps - 1);
            const y = cy - s * 0.5 + (t * 2 - 1) * vertHalfSpan;
            if (leftMax > pad) {
                const pt = clampPick(leftMax, y);
                if (pt.x >= 0)
                    return pt;
            }
            if (rightMin < bw) {
                const pt = clampPick(rightMin, y);
                if (pt.x >= 0)
                    return pt;
            }
        }

        for (let y = 0; y <= bh; y += 1) {
            for (let x = 0; x <= bw; x += 1) {
                if (!root.lockMarkerOverlapsThumb(x, y, barWidth, barHeight))
                    return Qt.point(x, y);
            }
        }
        return Qt.point(0, 0);
    }

    function rollLockMarker(barWidth: real, barHeight: real): void {
        const pt = root.randomLockMarkerOffset(barWidth, barHeight);
        root.lockMarkerX = pt.x;
        root.lockMarkerY = pt.y;
    }

    function engageLock(slug: string, barWidth: real, barHeight: real): void {
        if (!slug.length)
            return;
        root.lockedSlug = slug;
        root.rollLockMarker(barWidth, barHeight);
        root.planetLocked = true;
    }

    function releaseLock(): void {
        root.planetLocked = false;
        root.lockedSlug = "";
        root.lockMarkerX = -1;
        root.lockMarkerY = -1;
    }

    function wheelRotationDegForPlanetIndex(i: int): real {
        if (i < 0)
            return root.wheelRotationOffsetDeg;
        return (i - root.wheelZeroPlanetIndex) * root.wheelDegPerPlanetIndex + root.wheelRotationOffsetDeg;
    }

    function wheelRotationDegForSlug(slug: string): real {
        if (slug === "eye-of-the-universe")
            return 180;
        return root.wheelRotationDegForPlanetIndex(root.wheelPlanetSlugs.indexOf(slug));
    }

    function adoptWheelRingFromSlug(slug: string): void {
        wheelRingSpin.stop();
        root.wheelRingDisplayDeg = root.wheelRotationDegForSlug(slug);
    }

    function _spinWheelRingToSlug(slug: string): void {
        if (!slug.length)
            return;
        const from = root.wheelRingDisplayDeg;
        const to = root.wheelRotationDegForSlug(slug);
        if (Math.abs(to - from) < 0.5)
            return;
        wheelRingSpin.stop();
        wheelRingSpin.from = from;
        wheelRingSpin.to = to;
        wheelRingSpin.start();
    }

    function _systemBusy(): bool {
        return root.active || fadeOut.running || pickProc.running || postSpinFadeTimer.running;
    }

    function _enqueue(req: var): void {
        if (root.planetLocked)
            return;
        if (!root._systemBusy()) {
            root._startRequest(req);
            return;
        }
        if (root._requestQueue.length >= 2)
            return;
        const next = root._requestQueue.slice();
        next.push(req);
        root._requestQueue = next;
    }

    function _dequeue(): var {
        if (!root._requestQueue.length)
            return null;
        const first = root._requestQueue[0];
        root._requestQueue = root._requestQueue.slice(1);
        return first;
    }

    function _drainQueueAfterIdle(): void {
        if (root._systemBusy())
            return;
        const next = root._dequeue();
        if (next)
            root._startRequest(next);
    }

    function _startRequest(req: var): void {
        if (root.planetLocked)
            return;
        if (req.random)
            root._beginRandomPick();
        else if (req.slug && req.slug.length)
            root._beginSlugTransition(req.slug);
    }

    function _beginSlugTransition(slug: string): void {
        if (root.planetLocked)
            return;
        root.pendingApplySlug = slug;
        root._spinWheelRingToSlug(slug);
        postSpinFadeTimer.restart();
    }

    function _beginRandomPick(): void {
        root._pickResolvedSlug = "";
        pickProc.command = [
            "bash",
            "-c",
            "read -r QM <\"" + Paths.home + "/.config/caelestia/quantum-moon-root\" && [[ -n \"$QM\" ]] && [[ -f \"$QM/scripts/qm-random-walk.py\" ]] && exec python3 \"$QM/scripts/qm-random-walk.py\" pick"
        ];
        pickProc.running = true;
    }

    function _onPickProcExited(exitCode: int): void {
        const slug = root._pickResolvedSlug.length ? root._pickResolvedSlug : pickStdout.text.trim();
        root._pickResolvedSlug = "";
        if (exitCode !== 0 || !slug.length) {
            root._drainQueueAfterIdle();
            return;
        }
        if (root.planetLocked) {
            root._drainQueueAfterIdle();
            return;
        }
        root._beginSlugTransition(slug);
    }

    function start(): void {
        if (root.planetLocked)
            return;
        root._enqueue({
            random: true,
            slug: ""
        });
    }

    function startInstant(): void {
        root.startInstantThen(null);
    }

    function startInstantThen(callback: var): void {
        if (root.planetLocked) {
            if (callback)
                callback();
            return;
        }
        if (callback) {
            if (root._instantDoneCallback) {
                const prev = root._instantDoneCallback;
                root._instantDoneCallback = function () {
                    prev();
                    callback();
                };
            } else {
                root._instantDoneCallback = callback;
            }
        }
        if (instantProc.running)
            return;
        instantProc.command = ["bash", "-c", "f='" + Paths.home + "/.config/caelestia/quantum-moon-root'; [[ -f \"$f\" ]] && read -r QM < \"$f\" && \"$QM/scripts/qm-random\""];
        instantProc.running = true;
    }

    function _finishInstantShuffle(): void {
        const cb = root._instantDoneCallback;
        root._instantDoneCallback = null;
        if (cb)
            cb();
    }

    function applyPlanetSlug(slug: string): void {
        if (root.planetLocked)
            return;
        if (!slug.length)
            return;
        root._enqueue({
            random: false,
            slug: slug
        });
    }

    Process {
        id: proc

        onExited: function (exitCode, exitStatus) {
            fadeIn.start();
        }
    }

    Process {
        id: instantProc

        onExited: root._finishInstantShuffle()
    }

    Process {
        id: pickProc

        stdout: StdioCollector {
            id: pickStdout

            onStreamFinished: {
                root._pickResolvedSlug = text.trim();
            }
        }

        onExited: function (exitCode, exitStatus) {
            pickExitDefer.exitCode = exitCode;
            pickExitDefer.start();
        }
    }

    Timer {
        id: pickExitDefer

        interval: 0
        repeat: false
        property int exitCode: 0

        onTriggered: root._onPickProcExited(exitCode)
    }

    Timer {
        id: postSpinFadeTimer

        interval: root.wheelSpinLeadMs
        repeat: false

        onTriggered: {
            root.active = true;
            fadeOut.start();
        }
    }

    NumberAnimation {
        id: fadeOut

        target: root
        property: "overlayOpacity"
        from: 0
        to: 1
        duration: 1000
        easing.type: Easing.InOutQuad
        onFinished: {
            var slug = root.pendingApplySlug;
            root.pendingApplySlug = "";
            if (slug.length) {
                proc.command = [
                    "bash",
                    "-c",
                    "read -r QM <\"" + Paths.home + "/.config/caelestia/quantum-moon-root\" && [[ -n \"$QM\" ]] && [[ -f \"$QM/scripts/qm-apply\" ]] && exec bash \"$QM/scripts/qm-apply\" \"$1\"",
                    "_",
                    slug
                ];
            } else {
                proc.command = ["bash", "-c", "f='" + Paths.home + "/.config/caelestia/quantum-moon-root'; [[ -f \"$f\" ]] && read -r QM < \"$f\" && \"$QM/scripts/qm-random\""];
            }
            proc.running = true;
        }
    }

    NumberAnimation {
        id: fadeIn

        target: root
        property: "overlayOpacity"
        from: 1
        to: 0
        duration: 1000
        easing.type: Easing.InOutQuad
        onFinished: {
            root.active = false;
            root._drainQueueAfterIdle();
        }
    }

    FileView {
        id: lockStateView

        path: root.lockStateFile
        watchChanges: true
        printErrors: false

        onLoaded: {
            if (root._ignoreLockStateFileOnce) {
                root._ignoreLockStateFileOnce = false;
                return;
            }
            root.applyLockState(text());
        }
        onFileChanged: {
            if (root._ignoreLockStateFileOnce) {
                root._ignoreLockStateFileOnce = false;
                return;
            }
            reload();
        }
        onLoadFailed: function (err) {
            if (err === FileViewError.FileNotFound)
                root.applyLockState("");
            else
                root._lockStateHydrated = true;
        }
    }

    function applyLockState(data: string): void {
        root._applyingLockFromDisk = true;
        let locked = false;
        let slug = "";
        let mx = -1;
        let my = -1;
        try {
            if (data.length) {
                const j = JSON.parse(data);
                locked = j.planetLocked === true;
                slug = j.lockedSlug || "";
                if (typeof j.lockMarkerX === "number")
                    mx = j.lockMarkerX;
                if (typeof j.lockMarkerY === "number")
                    my = j.lockMarkerY;
            }
        } catch (e) {}
        root.lockedSlug = slug;
        root.lockMarkerX = mx;
        root.lockMarkerY = my;
        root._lockSlugMissing = locked && !slug.length;
        root._pendingLockMarkerRoll = locked && !root.isLockMarkerPlacementValid(mx, my, root.lockMarkerBarWidth, root.lockMarkerBarHeight);
        root.planetLocked = locked;
        root._applyingLockFromDisk = false;
        root._lockStateHydrated = true;
    }

    function persistLockState(): void {
        root._ignoreLockStateFileOnce = true;
        const dir = Paths.home + "/.local/state/quantum-moon";
        const path = dir + "/state.json";
        let body = "{\"planetLocked\":" + (root.planetLocked ? "true" : "false");
        if (root.planetLocked) {
            body += ",\"lockedSlug\":\"" + root.lockedSlug + "\"";
            body += ",\"lockMarkerX\":" + root.lockMarkerX + ",\"lockMarkerY\":" + root.lockMarkerY;
        }
        body += "}";
        const escaped = body.replace(/'/g, "'\\''");
        writeLockStateProc.command = ["sh", "-c", "mkdir -p \"" + dir + "\" && printf '%s' '" + escaped + "' >\"" + path + "\""];
        writeLockStateProc.running = true;
    }

    onPlanetLockedChanged: {
        if (root.planetLocked) {
            root._requestQueue = [];
            postSpinFadeTimer.stop();
            wheelRingSpin.stop();
            root.pendingApplySlug = "";
        }
        if (!root._applyingLockFromDisk && root._lockStateHydrated)
            root.persistLockState();
    }

    Process {
        id: writeLockStateProc
    }
}
