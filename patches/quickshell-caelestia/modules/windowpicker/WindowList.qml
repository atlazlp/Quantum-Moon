pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import qs.modules.windowpicker.items

StyledListView {
    id: root

    required property StyledTextField search
    required property DrawerVisibilities visibilities
    required property var onKillRequest
    property bool muteKeys: false

    property var memoryByPid: ({})
    property int memoryRev: 0

    signal killRequested(var rowData)

    function formatRam(kb: int): string {
        if (!kb || kb <= 0)
            return "";
        const mib = kb / 1024;
        if (mib >= 1024)
            return `${(mib / 1024).toFixed(1)} GB`;
        if (mib >= 100)
            return `${Math.round(mib)} MB`;
        if (mib >= 10)
            return `${Math.round(mib)} MB`;
        return `${mib.toFixed(1)} MB`;
    }

    Timer {
        id: memTimer

        interval: 2000
        repeat: true
        running: root.visibilities?.windowPicker ?? false
        onTriggered: memProc.running = true
    }

    Connections {
        target: root.visibilities

        function onWindowPickerChanged(): void {
            if (root.visibilities.windowPicker)
                memProc.running = true;
        }
    }

    Process {
        id: memProc

        command: ["sh", "-c", "ps -eo pid=,rss= --no-headers 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {};
                for (const line of text.trim().split("\n")) {
                    if (!line)
                        continue;
                    const parts = line.trim().split(/\s+/);
                    if (parts.length < 2)
                        continue;
                    const pid = parseInt(parts[0], 10);
                    const kb = parseInt(parts[1], 10);
                    if (pid > 0 && kb >= 0)
                        map[pid] = kb;
                }
                root.memoryByPid = map;
                root.memoryRev++;
            }
        }
    }

    model: ScriptModel {
        id: model

        onValuesChanged: root.currentIndex = 0

        values: {
            const _rev = LauncherItemOverrides.revision;
            const _mem = root.memoryRev;
            const memMap = root.memoryByPid;
            const q = (root.search.text ?? "").toLowerCase();
            const vals = Hypr.toplevels?.values;

            function formatHyprAddress(addr): string {
                if (addr === undefined || addr === null)
                    return "";
                if (typeof addr === "number" && Number.isFinite(addr))
                    return `0x${Math.trunc(addr).toString(16)}`;
                let s = String(addr).trim();
                if (!s)
                    return "";
                if (s.startsWith("0x") || s.startsWith("0X"))
                    return `0x${s.slice(2).toLowerCase()}`;
                return `0x${s.toLowerCase()}`;
            }

            function isListableToplevel(c): bool {
                const lo = c?.lastIpcObject;
                if (!lo)
                    return false;
                if (lo.mapped === false || lo.hidden === true)
                    return false;
                if (!formatHyprAddress(c.address))
                    return false;
                const sz = lo.size;
                if (Array.isArray(sz) && sz[0] === 0 && sz[1] === 0)
                    return false;
                const klass = (lo.class ?? lo.initialClass ?? "").toString().trim();
                const title = (lo.title ?? lo.initialTitle ?? "").toString().trim();
                return !!(klass || title);
            }

            const sep = /\s+[\-\u2013\u2014]\s+/;
            const knownSuffixes = new Set([
                "mozilla firefox",
                "firefox",
                "librewolf",
                "waterfox",
                "google chrome",
                "chromium",
                "chromium browser",
                "microsoft edge",
                "msedge",
                "brave",
                "brave browser",
                "tor browser",
                "safari",
                "cursor",
                "visual studio code",
                "code",
                "vscodium",
                "github desktop",
                "thunar",
                "nautilus",
                "pcmanfm",
                "nemo",
                "gedit",
                "kate",
                "foot",
                "kitty",
                "alacritty",
                "wezterm",
            ]);

            function stripTrailingAppSegments(rawTitle, klass) {
                const t = (rawTitle ?? "").toString().trim();
                if (!t)
                    return "";
                const klassKey = (klass ?? "").toString().trim().toLowerCase();
                const klassSpaced = klassKey.replace(/-/g, " ");
                let parts = t.split(sep).map(p => p.trim()).filter(p => p.length);
                if (parts.length < 2)
                    return t;

                function tailIsAppNoise(seg) {
                    const s = seg.trim().toLowerCase();
                    if (!s)
                        return false;
                    if (knownSuffixes.has(s))
                        return true;
                    if (klassKey && (s === klassKey || s === klassSpaced))
                        return true;
                    return false;
                }

                while (parts.length >= 2 && tailIsAppNoise(parts[parts.length - 1]))
                    parts.pop();
                return parts.length ? parts.join(" - ") : t;
            }

            let rows = [];
            if (vals && typeof vals.filter === "function") {
                rows = vals.filter(isListableToplevel).map(c => {
                    const lo = c.lastIpcObject;
                    const klass = (lo.class ?? lo.initialClass ?? "").toString().trim();
                    const rawTitle = (lo.title ?? lo.initialTitle ?? "").toString().trim();
                    let line = rawTitle ? stripTrailingAppSegments(rawTitle, klass) : "";
                    if (!line)
                        line = klass || "?";
                    line = LauncherItemOverrides.displayLabel("window", klass, line);
                    const subtitle = LauncherItemOverrides.subtitle("window", klass, klass);
                    const pid = typeof lo.pid === "number" ? lo.pid : parseInt(lo.pid, 10) || 0;
                    const ramKb = pid > 0 ? (memMap[pid] ?? 0) : 0;
                    const searchText = `${klass} ${rawTitle} ${line} ${subtitle}`.toLowerCase();
                    return {
                        address: formatHyprAddress(c.address),
                        pid,
                        line,
                        klass,
                        subtitle,
                        ramKb,
                        ramLabel: root.formatRam(ramKb),
                        searchText,
                        title: rawTitle
                    };
                });
                rows.sort((a, b) => {
                    const dr = (b.ramKb ?? 0) - (a.ramKb ?? 0);
                    if (dr !== 0)
                        return dr;
                    const c = a.line.localeCompare(b.line);
                    if (c !== 0)
                        return c;
                    return (a.title || "").localeCompare(b.title || "");
                });
            }
            if (q)
                rows = rows.filter(r => r.searchText.includes(q));
            return rows;
        }
    }

    spacing: Tokens.spacing.small
    orientation: Qt.Vertical
    keyNavigationEnabled: !root.muteKeys
    interactive: !root.muteKeys

    readonly property int rowStep: Tokens.sizes.launcher.itemHeight + spacing
    readonly property int listMinRows: 6

    implicitHeight: Math.max(
        listMinRows * rowStep - spacing,
        rowStep * Math.min(Config.launcher.maxShown, Math.max(1, count)) - spacing
    )

    preferredHighlightBegin: 0
    preferredHighlightEnd: height
    highlightRangeMode: ListView.ApplyRange

    highlightFollowsCurrentItem: false
    highlight: StyledRect {
        radius: Tokens.rounding.normal
        color: Colours.palette.m3onSurface
        opacity: 0.08

        y: root.currentItem?.y ?? 0
        implicitWidth: root.width
        implicitHeight: root.currentItem?.implicitHeight ?? 0

        Behavior on y {
            Anim {
                type: Anim.DefaultSpatial
            }
        }
    }

    StyledScrollBar.vertical: StyledScrollBar {
        flickable: root
    }

    add: Transition {
        Anim {
            properties: "opacity,scale"
            from: 0
            to: 1
        }
    }

    remove: Transition {
        Anim {
            properties: "opacity,scale"
            from: 1
            to: 0
        }
    }

    move: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    addDisplaced: Transition {
        Anim {
            property: "y"
            type: Anim.StandardSmall
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    displaced: Transition {
        Anim {
            property: "y"
        }
        Anim {
            properties: "opacity,scale"
            to: 1
        }
    }

    delegate: WindowRow {
        visibilities: root.visibilities
        onKillRequest: row => {
            if (typeof root.onKillRequest === "function")
                root.onKillRequest(row);
            else
                root.killRequested(row);
        }
    }
}
