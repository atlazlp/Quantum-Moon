pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia

Singleton {
    id: root

    readonly property string stateFile: Paths.home + "/.local/state/quantum-moon/current.json"
    readonly property string rootFile: Paths.home + "/.config/caelestia/quantum-moon-root"
    readonly property string videoStateFile: Paths.home + "/.local/state/quantum-moon/last-video.path"

    property string slug: ""
    property string qmRoot: ""
    property string videoState: ""

    FileView {
        path: root.rootFile
        watchChanges: true
        printErrors: false

        onLoaded: root.qmRoot = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.qmRoot = ""
    }

    FileView {
        path: root.stateFile
        watchChanges: true
        printErrors: false

        onLoaded: root.parseSlug(text())
        onFileChanged: reload()
        onLoadFailed: root.slug = ""
    }

    FileView {
        path: root.videoStateFile
        watchChanges: true
        printErrors: false

        onLoaded: root.videoState = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.videoState = ""
    }

    function parseSlug(data: string): void {
        try {
            const j = JSON.parse(data);
            root.slug = j.slug || "";
        } catch (e) {
            root.slug = "";
        }
    }

    function sortedMonitors(): var {
        const list = [...Hyprland.monitors.values];
        list.sort((a, b) => {
            if (a.x !== b.x)
                return a.x - b.x;
            return a.y - b.y;
        });
        return list;
    }

    function slotIndexForScreen(screenName: string): int {
        const list = root.sortedMonitors();
        const idx = list.findIndex(m => m.name === screenName);
        if (idx < 0)
            return 0;
        return Math.min(idx, 2);
    }

    function centerScreenName(): string {
        const list = root.sortedMonitors();
        if (list.length === 0)
            return "";
        const idx = list.length >= 2 ? 1 : 0;
        return list[idx].name;
    }

    function centerUsesVideo(): bool {
        const s = root.videoState;
        if (!s.length)
            return false;
        if (s.startsWith("missing:") || s.startsWith("no-mpvpaper") || s.startsWith("lfs-pointer:")
                || s === "no-monitor" || s.startsWith("mpvpaper-exit:"))
            return false;
        return true;
    }

    function slotPathForScreen(screenName: string): string {
        if (!root.qmRoot.length || !root.slug.length)
            return "";
        const idx = root.slotIndexForScreen(screenName);
        return root.qmRoot + "/modes/" + root.slug + "/wallpapers/slot-" + idx + ".png";
    }

    function shouldShowOnScreen(screenName: string): bool {
        const path = root.slotPathForScreen(screenName);
        if (!path.length)
            return false;
        if (root.centerUsesVideo() && screenName === root.centerScreenName())
            return false;
        return true;
    }
}
