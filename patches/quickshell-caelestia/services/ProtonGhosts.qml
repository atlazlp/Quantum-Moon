pragma Singleton

import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    function shellGuardEnabled(): bool {
        return hasProtonGameWindow() && !hasProtonFullscreen();
    }

    function stickyLauncherUi(launcherOpen: bool, pickerOpen: bool): bool {
        return shellGuardEnabled() && (launcherOpen || pickerOpen);
    }

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

    function steamClass(klass: string): bool {
        return klass.startsWith("steam_app_") || klass === "steam_proton";
    }

    function isSteamIpcObject(lo: var): bool {
        if (!lo || lo.mapped === false || lo.hidden === true)
            return false;
        const klass = (lo.class ?? lo.initialClass ?? "").toString().trim();
        return steamClass(klass);
    }

    function isGhostIpcObject(lo: var): bool {
        if (!isSteamIpcObject(lo))
            return false;

        const title = (lo.title ?? lo.initialTitle ?? "").toString().trim();
        if (title)
            return false;

        const sz = lo.size;
        if (!Array.isArray(sz) || sz.length < 2)
            return false;

        const w = Number(sz[0]);
        const h = Number(sz[1]);
        if (!(w > 0) && !(h > 0))
            return false;

        return h <= 30 && w <= 220;
    }

    function isProtonGameIpcObject(lo: var): bool {
        return isSteamIpcObject(lo) && !isGhostIpcObject(lo);
    }

    function hasProtonGameWindow(): bool {
        const vals = Hypr.toplevels?.values;
        if (!vals || typeof vals.some !== "function")
            return false;
        return vals.some(t => isProtonGameIpcObject(t?.lastIpcObject));
    }

    function hasProtonFullscreen(): bool {
        const vals = Hypr.toplevels?.values;
        if (!vals || typeof vals.some !== "function")
            return false;
        return vals.some(t => {
            const lo = t?.lastIpcObject;
            if (!isProtonGameIpcObject(lo))
                return false;
            const fs = lo.fullscreen ?? 0;
            const fsc = lo.fullscreenClient ?? 0;
            return fs > 1 || fsc > 1;
        });
    }

    function activeFocusIsGhost(): bool {
        return isGhostIpcObject(Hypr.activeToplevel?.lastIpcObject);
    }

    function dismissActiveGhost(): void {
        const t = Hypr.activeToplevel;
        if (!t || !isGhostIpcObject(t.lastIpcObject))
            return;
        const addr = formatHyprAddress(t.address);
        if (addr)
            Hypr.dispatch(`closewindow address:${addr}`);
    }
}
