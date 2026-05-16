pragma Singleton

import Quickshell
import qs.components
import qs.services

Singleton {
    property var screens: new Map()
    property var bars: new Map()

    function load(screen: ShellScreen, visibilities: DrawerVisibilities): void {
        screens.set(screen.name, visibilities);
    }

    function getForActive(): DrawerVisibilities {
        const mon = Hypr.focusedMonitor
        const key = mon && mon.name ? mon.name : ""
        return screens.get(key)
    }
}
