pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

Singleton {
    id: root

    readonly property string iconsDir: `${Paths.data}/launcher-icons`
    readonly property string storePath: `${Paths.state}/launcher-item-overrides.json`

    property var data: ({
            apps: {},
            windows: {}
        })
    property bool loaded: false

    property var editTarget: null
    property string editScreen: ""
    readonly property bool editOpen: editTarget !== null && editTarget !== undefined

    property int revision: 0

    property var launchTimestamp: 0
    property var launcherClearTimestamp: 0

    function launcherJustCleared(): bool {
        return (Date.now() - launcherClearTimestamp) < 500;
    }

    function noteLaunch(visibilities: var): void {
        launchTimestamp = Date.now();
        if (visibilities) {
            visibilities.windowPicker = false;
            visibilities.launcher = false;
        }
    }

    function launcherJustUsed(): bool {
        return (Date.now() - launchTimestamp) < 800;
    }

    function openEditor(target: var): void {
        editScreen = (target?.screen ?? "").toString();
        editTarget = target;
    }

    function closeEditor(): void {
        editTarget = null;
        editScreen = "";
    }

    function safeKey(key: string): string {
        return (key ?? "").toString().trim().replace(/[^a-zA-Z0-9._-]+/g, "_") || "item";
    }

    function bucket(type: string): string {
        return type === "window" ? "windows" : "apps";
    }

    function entry(type: string, key: string): var {
        const b = root.data[bucket(type)];
        if (!b || !key)
            return null;
        return b[key] ?? null;
    }

    function displayLabel(type: string, key: string, fallback: string): string {
        const e = entry(type, key);
        const label = (e?.label ?? "").toString().trim();
        return label || fallback;
    }

    function subtitle(type: string, key: string, fallback: string): string {
        const e = entry(type, key);
        const sub = (e?.subtitle ?? "").toString().trim();
        return sub || fallback;
    }

    function iconSource(type: string, key: string, fallback: string): string {
        const e = entry(type, key);
        const file = (e?.iconFile ?? "").toString().trim();
        if (file)
            return Qt.resolvedUrl(`${iconsDir}/${file}`);
        return fallback;
    }

    function extensionFor(path: string): string {
        const m = path.toLowerCase().match(/\.([a-z0-9]+)$/);
        if (!m)
            return "png";
        const ext = m[1];
        if (ext === "jpeg")
            return "jpg";
        return ext;
    }

    function deleteIconFile(fileName: string): void {
        const name = (fileName ?? "").toString().trim();
        if (!name)
            return;
        CUtils.deleteFile(Qt.resolvedUrl(`${iconsDir}/${name}`));
    }

    function copyIcon(type: string, key: string, sourcePath: string): string {
        const ext = extensionFor(sourcePath);
        const destName = `${safeKey(key)}.${ext}`;
        const destUrl = Qt.resolvedUrl(`${iconsDir}/${destName}`);
        Quickshell.execDetached(["mkdir", "-p", iconsDir]);
        const prev = entry(type, key)?.iconFile;
        if (prev && prev !== destName)
            deleteIconFile(prev);
        if (!CUtils.copyFile(Qt.resolvedUrl(sourcePath), destUrl))
            return "";
        return destName;
    }

    function saveOverride(type: string, key: string, labelVal: string, subtitleVal: string, iconSourcePath: string): bool {
        if (!key)
            return false;

        const b = bucket(type);
        const next = JSON.parse(JSON.stringify(root.data));
        if (!next[b])
            next[b] = {};

        const prev = next[b][key] ?? {};
        const record = {
            label: (labelVal ?? "").toString().trim(),
            subtitle: (subtitleVal ?? "").toString().trim(),
            iconFile: prev.iconFile ?? ""
        };

        if (iconSourcePath) {
            const copied = copyIcon(type, key, iconSourcePath);
            if (!copied)
                return false;
            record.iconFile = copied;
        }

        if (!record.label && !record.subtitle && !record.iconFile) {
            delete next[b][key];
        } else {
            next[b][key] = record;
        }

        root.data = next;
        root.revision++;
        persist();
        return true;
    }

    function resetOverride(type: string, key: string): void {
        if (!key)
            return;

        const b = bucket(type);
        const next = JSON.parse(JSON.stringify(root.data));
        if (!next[b] || !next[b][key])
            return;

        deleteIconFile(next[b][key]?.iconFile);
        delete next[b][key];
        root.data = next;
        root.revision++;
        persist();
    }

    function persist(): void {
        if (!loaded)
            return;
        saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 200
        onTriggered: storage.setText(JSON.stringify(root.data, null, 2))
    }

    FileView {
        id: storage

        printErrors: false
        path: root.storePath
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                root.data = {
                    apps: parsed?.apps ?? {},
                    windows: parsed?.windows ?? {}
                };
            } catch (e) {
                root.data = {
                    apps: {},
                    windows: {}
                };
            }
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText(JSON.stringify({
                            apps: {},
                            windows: {}
                        }, null, 2)));
            }
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", iconsDir])
}
