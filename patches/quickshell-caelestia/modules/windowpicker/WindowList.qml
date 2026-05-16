pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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

    signal killRequested(var rowData)

    model: ScriptModel {
        id: model

        onValuesChanged: root.currentIndex = 0

        values: {
            const q = (root.search.text ?? "").toLowerCase();
            const vals = Hypr.toplevels?.values;
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
                rows = vals.filter(c => c?.lastIpcObject).map(c => {
                    const lo = c.lastIpcObject;
                    const klass = (lo.class ?? "").toString().trim();
                    const rawTitle = (lo.title ?? "").toString().trim();
                    const line = rawTitle ? stripTrailingAppSegments(rawTitle, klass) : "?";
                    const searchText = `${klass} ${rawTitle}`.toLowerCase();
                    return {
                        address: String(c.address ?? ""),
                        pid: typeof lo.pid === "number" ? lo.pid : parseInt(lo.pid, 10) || 0,
                        line,
                        klass,
                        searchText,
                        title: rawTitle
                    };
                });
                rows.sort((a, b) => {
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
