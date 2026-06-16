import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts
import qs.utils

CustomMouseArea {
    id: root

    required property ShellScreen screen
    Config.screen: screen.name
    required property BarPopouts.Wrapper popouts
    required property DrawerVisibilities visibilities
    required property Panels panels
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen

    readonly property bool sidebarAllowedOnThisOutput: Config.sidebar.enabled
    readonly property var hoverExcludedScreens: Config.bar.hoverExcludedScreens ?? []
    readonly property bool hoverDisabled: Strings.testRegexList(hoverExcludedScreens, screen.name)

    property point dragStart
    property bool launcherShortcutActive
    property bool windowPickerShortcutActive
    property bool windowPickerDismissedSideways
    property bool dashboardShortcutActive
    property bool quantumMoonShortcutActive
    property bool osdShortcutActive
    property bool sidebarShortcutActive
    property bool utilitiesShortcutActive

    property real pointerX
    property real pointerY
    property bool hyprCursorHere

    function handlePointerLeave(): void {
        if (!osdShortcutActive) {
            visibilities.osd = false;
            root.panels.osd.hovered = false;
        }

        if (!dashboardShortcutActive)
            visibilities.dashboard = false;

        if (!quantumMoonShortcutActive)
            visibilities.quantumMoon = false;

        if (!utilitiesShortcutActive)
            visibilities.utilities = false;

        if (!sidebarShortcutActive)
            visibilities.sidebar = false;

        if (Config.launcher.showOnHover && !launcherShortcutActive && !ProtonGhosts.stickyLauncherUi(visibilities.launcher && Config.launcher.enabled, visibilities.windowPicker))
            visibilities.launcher = false;

        if (!windowPickerShortcutActive && (!visibilities.windowPicker || !pickerKeepOpen(pointerX, pointerY)))
            visibilities.windowPicker = false;

        if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }

        if (Config.bar.showOnHover)
            bar.isHovered = false;
    }

    function applyPointerPosition(x: real, y: real): void {
        pointerX = x;
        pointerY = y;

        if (popouts.isDetached)
            return;

        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);
            return;
        }

        if (hoverDisabled || KvmCapture.active) {
            if (!dashboardShortcutActive)
                visibilities.dashboard = false;
            if (!quantumMoonShortcutActive)
                visibilities.quantumMoon = false;
            if (!utilitiesShortcutActive)
                visibilities.utilities = false;
            if (!launcherShortcutActive)
                visibilities.launcher = false;
            if (!windowPickerShortcutActive)
                visibilities.windowPicker = false;
            popouts.hasCurrent = false;
            bar.closeTray();
            return;
        }

        if (visibilities.sidebar && sidebarAllowedOnThisOutput) {
            const inSidebar = inSidebarBounds(x, y);
            if (!sidebarShortcutActive && !inSidebar)
                visibilities.sidebar = false;
            else if (sidebarShortcutActive && inSidebar)
                sidebarShortcutActive = false;
        }

        if (Config.launcher.showOnHover && !visibilities.launcher && inBottomPanel(panels.launcher, x, y) && canOpenWindowPicker())
            visibilities.launcher = true;

        const launcherOpen = visibilities.launcher && Config.launcher.enabled;
        const pickerOpen = visibilities.windowPicker;
        const inBottomLauncherBand = Config.launcher.showOnHover && inScreenBottomLauncherBand(y);
        const launcherPriority = launcherOpen || pickerOpen || inBottomLauncherBand;

        if (launcherPriority) {
            popouts.hasCurrent = false;
            bar.closeTray();
            if (Config.bar.showOnHover && !visibilities.bar)
                bar.isHovered = false;
        }

        if (Config.launcher.showOnHover && launcherOpen && !launcherShortcutActive && !ProtonGhosts.stickyLauncherUi(launcherOpen, pickerOpen) && !isOverLauncherBounds(x, y))
            visibilities.launcher = false;

        if (!Config.launcher.showOnHover && pickerOpen) {
            const keepPicker = pickerKeepOpen(x, y);
            const animating = (panels.windowPicker.offsetScale ?? 0) > 0.001 && (panels.windowPicker.offsetScale ?? 0) < 0.999;
            if (!windowPickerShortcutActive && !keepPicker && !(animating && inWindowPickerBottomHover(x, y))) {
                const exitedSides = !windowPickerWithinWidth(x);
                visibilities.windowPicker = false;
                if (exitedSides && windowPickerBottomBand(y))
                    windowPickerDismissedSideways = true;
            } else if (windowPickerShortcutActive && keepPicker) {
                windowPickerShortcutActive = false;
            }
        }

        if (inWindowPickerBottomHover(x, y) || !windowPickerBottomBand(y))
            windowPickerDismissedSideways = false;

        if ((launcherOpen && (isOverLauncherBounds(x, y) || inLauncherVerticalBand(y))) || (pickerOpen && pickerKeepOpen(x, y)))
            return;

        if (!bar.disabled && !visibilities.bar && Config.bar.showOnHover && x < bar.clampedWidth && !launcherPriority)
            bar.isHovered = true;

        if (!bar.disabled && pressed && dragStart.x < bar.clampedWidth) {
            if (dragX > Config.bar.dragThreshold)
                visibilities.bar = true;
            else if (dragX < -Config.bar.dragThreshold)
                visibilities.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);

            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;

                if (root.sidebarAllowedOnThisOutput && showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    visibilities.sidebar = true;
            } else if (root.sidebarAllowedOnThisOutput && showSidebar && dragX < -Config.sidebar.dragThreshold) {
                visibilities.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;
            }

            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                visibilities.sidebar = false;
        }

        if (!Config.launcher.showOnHover && !launcherOpen && !pickerOpen && !pressed && canOpenWindowPicker()) {
            if (!windowPickerDismissedSideways && inBottomPanel(panels.windowPicker, x, y))
                visibilities.windowPicker = true;
        }
        if (!Config.launcher.showOnHover && pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold && !ProtonGhosts.stickyLauncherUi(launcherOpen, pickerOpen))
                visibilities.launcher = false;
        }

        const showDashboard = Config.dashboard.enabled && Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);

        if (!dashboardShortcutActive) {
            visibilities.dashboard = showDashboard;
        } else if (showDashboard) {
            dashboardShortcutActive = false;
        }

        const showQuantumMoon = GlobalConfig.quantumMoon?.enabled !== false && GlobalConfig.quantumMoon?.showOnHover !== false && inTopPanel(panels.quantumMoonPanel, x, y);

        if (!quantumMoonShortcutActive) {
            visibilities.quantumMoon = showQuantumMoon;
        } else if (showQuantumMoon) {
            quantumMoonShortcutActive = false;
        }

        if (pressed && Config.dashboard.enabled && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                visibilities.dashboard = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                visibilities.dashboard = false;
        }

        if (GlobalConfig.quantumMoon?.enabled !== false && pressed && inTopPanel(panels.quantumMoonPanel, dragStart.x, dragStart.y) && withinPanelWidth(panels.quantumMoonPanel, x, y)) {
            if (dragY > Config.dashboard.dragThreshold)
                visibilities.quantumMoon = true;
            else if (dragY < -Config.dashboard.dragThreshold)
                visibilities.quantumMoon = false;
        }

        const showUtilities = inBottomPanel(panels.utilities, x, y);

        if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            utilitiesShortcutActive = false;
        }

        if (!hoverDisabled && !bar.disabled && x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else if (!launcherPriority && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    function canOpenWindowPicker(): bool {
        if (LauncherItemOverrides.editOpen)
            return false;
        if (visibilities.launcher)
            return false;
        if (panels.launcher.offsetScale < 1.0)
            return false;
        if (LauncherItemOverrides.launcherJustUsed())
            return false;
        return true;
    }

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.borderThickness + panel.y;
        return y >= panelY - Config.border.rounding && y <= panelY + panel.height + Config.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = bar.implicitWidth + panel.x;
        return x >= panelX - Config.border.rounding && x <= panelX + panel.width + Config.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < bar.implicitWidth + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inSidebarBounds(x: real, y: real): bool {
        if (!sidebarAllowedOnThisOutput)
            return false;
        return inRightPanel(panels.sidebar, x, y) && withinPanelHeight(panels.sidebar, x, y);
    }

    function inBottomHoverBand(y: real): bool {
        return y > height - LayoutTweaks.bottomHoverTriggerPx - Config.border.rounding;
    }

    function panelClosedForHover(panel: Item): bool {
        if (panel.shouldBeActive !== undefined) // qmllint disable missing-property
            return !panel.shouldBeActive;
        return (panel.offsetScale ?? 0) >= 0.999; // qmllint disable missing-property
    }

    function bottomHoverTriggerHeight(panel: Item): real {
        if (panelClosedForHover(panel))
            return LayoutTweaks.bottomHoverTriggerPx;
        const scale = panel.offsetScale ?? 0; // qmllint disable missing-property
        const revealed = panel.height * (1 - scale);
        return Math.max(revealed, LayoutTweaks.bottomHoverTriggerPx);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        if (hoverDisabled)
            return false;
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real): bool {
        if (hoverDisabled)
            return false;
        const triggerHeight = bottomHoverTriggerHeight(panel);
        return y > height - triggerHeight && withinPanelWidth(panel, x, y);
    }

    function inScreenBottomLauncherBand(y: real): bool {
        if (hoverDisabled)
            return false;
        return inBottomHoverBand(y);
    }

    function inLauncherVerticalBand(y: real): bool {
        if (hoverDisabled)
            return false;
        const lh = bottomHoverTriggerHeight(panels.launcher);
        return y > height - lh - Config.border.rounding;
    }

    function isOverLauncherBounds(x: real, y: real): bool {
        if (!Config.launcher.enabled)
            return false;
        const p = panels.launcher;
        const panelHeight = p.height * (1 - (p.offsetScale ?? 0));
        const left = bar.implicitWidth + p.x;
        const top = borderThickness + p.y + (p.height - panelHeight);
        return x >= left && x <= left + p.width && y >= top && y <= top + panelHeight;
    }

    function windowPickerWithinWidth(x: real): bool {
        const p = panels.windowPicker;
        const panelX = bar.implicitWidth + p.x;
        return x >= panelX && x <= panelX + p.width;
    }

    function windowPickerBottomBand(y: real): bool {
        if (hoverDisabled)
            return false;
        return inBottomHoverBand(y);
    }

    function inWindowPickerBottomHover(x: real, y: real): bool {
        return inBottomPanel(panels.windowPicker, x, y);
    }

    function pickerPointerBounds(x: real, y: real): bool {
        const p = panels.windowPicker;
        if (!visibilities.windowPicker)
            return inBottomPanel(p, x, y);
        if (!windowPickerWithinWidth(x))
            return false;
        if (inBottomHoverBand(y))
            return true;
        const panelHeight = p.height * (1 - (p.offsetScale ?? 0));
        if (panelHeight <= 0)
            return false;
        const top = borderThickness + p.y + (p.height - panelHeight);
        const bottom = borderThickness + p.y + p.height;
        return y >= top && y <= bottom;
    }

    function pickerKeepOpen(x: real, y: real): bool {
        if (!visibilities.windowPicker)
            return false;
        if (panels.windowPicker.pointerInside)
            return true;
        return pickerPointerBounds(x, y);
    }

    function isOverWindowPickerBounds(x: real, y: real): bool {
        return visibilities.windowPicker && pickerKeepOpen(x, y);
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        const lx = event.x;
        const ly = event.y;
        if (bar.disabled)
            return;
        if (lx < bar.implicitWidth && Config.launcher.showOnHover && inScreenBottomLauncherBand(ly))
            return;
        if (lx < bar.implicitWidth) {
            const barRoot = bar.content.item as Item;
            if (barRoot) {
                const p = barRoot.mapFromItem(this, lx, ly);
                bar.handleWheel(event.y, p.x, p.y, event.angleDelta);
            } else {
                bar.handleWheel(event.y, 0, 0, event.angleDelta);
            }
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    enabled: !LauncherItemOverrides.editOpen
    hoverEnabled: true

    onPressed: event => {
        dragStart = Qt.point(event.x, event.y);
        if (visibilities.sidebar && !inSidebarBounds(event.x, event.y)) {
            visibilities.sidebar = false;
            sidebarShortcutActive = false;
        }
    }
    onContainsMouseChanged: {
        if (!containsMouse && !Hypr.cursorOnScreen(screen))
            handlePointerLeave();
    }

    onPositionChanged: event => applyPointerPosition(event.x, event.y)

    Connections {
        target: Hypr

        function onCursorMoved(gx: real, gy: real): void {
            const here = Hypr.cursorOnScreen(root.screen);
            if (!here) {
                if (root.hyprCursorHere)
                    root.handlePointerLeave();
                root.hyprCursorHere = false;
                return;
            }

            root.hyprCursorHere = true;
            if (root.containsMouse)
                return;

            root.applyPointerPosition(gx - root.screen.x, gy - root.screen.y);
        }
    }

    Connections {
        target: panels.windowPicker

        function onPointerInsideChanged(): void {
            if (!root.visibilities.windowPicker)
                return;
            if (panels.windowPicker.pointerInside)
                return;
            if (Config.launcher.showOnHover || root.windowPickerShortcutActive)
                return;
            if (root.pickerKeepOpen(root.pointerX, root.pointerY))
                return;
            root.visibilities.windowPicker = false;
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            if (root.visibilities.launcher) {
                const inLauncherArea = root.isOverLauncherBounds(root.pointerX, root.pointerY) || root.inLauncherVerticalBand(root.pointerY);
                if (!inLauncherArea)
                    root.launcherShortcutActive = true;
            } else {
                root.launcherShortcutActive = false;
                root.dashboardShortcutActive = false;
                root.quantumMoonShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.pointerX, root.pointerY);
                const inQuantumArea = root.inTopPanel(root.panels.quantumMoonPanel, root.pointerX, root.pointerY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.pointerX, root.pointerY);

                if (!inDashboardArea) {
                    root.visibilities.dashboard = false;
                }
                if (!inQuantumArea) {
                    root.visibilities.quantumMoon = false;
                }
                if (!inOsdArea) {
                    root.visibilities.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.visibilities.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.pointerX, root.pointerY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onQuantumMoonChanged() {
            if (root.visibilities.quantumMoon) {
                const inQuantumArea = root.inTopPanel(root.panels.quantumMoonPanel, root.pointerX, root.pointerY);
                if (!inQuantumArea) {
                    root.quantumMoonShortcutActive = true;
                }
            } else {
                root.quantumMoonShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.visibilities.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.pointerX, root.pointerY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onWindowPickerChanged() {
            if (root.visibilities.windowPicker) {
                const inPickerArea = root.pickerKeepOpen(root.pointerX, root.pointerY);
                if (!inPickerArea) {
                    root.windowPickerShortcutActive = true;
                }
            } else {
                root.windowPickerShortcutActive = false;
                root.windowPickerDismissedSideways = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.visibilities.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.pointerX, root.pointerY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        function onSidebarChanged() {
            if (root.visibilities.sidebar) {
                if (!root.inSidebarBounds(root.pointerX, root.pointerY))
                    root.sidebarShortcutActive = true;
            } else {
                root.sidebarShortcutActive = false;
            }
        }

        target: root.visibilities
    }
}
