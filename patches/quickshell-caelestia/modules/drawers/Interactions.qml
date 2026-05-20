import QtQuick
import QtQuick.Controls
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.bar as Bar
import qs.modules.bar.popouts as BarPopouts

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

    property point dragStart
    property bool launcherShortcutActive
    property bool windowPickerShortcutActive
    property bool windowPickerDismissedSideways
    property bool dashboardShortcutActive
    property bool quantumMoonShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive

    function inStableBottomPanelZone(y: real): bool {
        const lh = panels.launcher.implicitHeight > 0 ? panels.launcher.implicitHeight : panels.launcher.height;
        const ph = panels.windowPicker.implicitHeight > 0 ? panels.windowPicker.implicitHeight : panels.windowPicker.height;
        const panelHeight = Math.max(lh, ph);
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - Config.border.rounding;
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

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function inScreenBottomLauncherBand(y: real): bool {
        const lh = panels.launcher.height * (1 - (panels.launcher.offsetScale ?? 0));
        const ph = panels.windowPicker.height * (1 - (panels.windowPicker.offsetScale ?? 0));
        const panelHeight = Math.max(lh, ph);
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - Config.border.rounding;
    }

    function inLauncherVerticalBand(y: real): bool {
        const lh = panels.launcher.height * (1 - (panels.launcher.offsetScale ?? 0));
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + lh) - Config.border.rounding;
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
        const p = panels.windowPicker;
        const panelHeight = p.height * (1 - (p.offsetScale ?? 0));
        return y > height - Math.max(Config.border.minThickness, Config.border.thickness + panelHeight) - Config.border.rounding;
    }

    function inWindowPickerBottomHover(x: real, y: real): bool {
        return windowPickerWithinWidth(x) && windowPickerBottomBand(y);
    }

    function pickerPointerBounds(x: real, y: real): bool {
        if (inWindowPickerBottomHover(x, y))
            return true;
        if (!windowPickerWithinWidth(x))
            return false;
        const p = panels.windowPicker;
        const panelHeight = p.height * (1 - (p.offsetScale ?? 0));
        if (panelHeight <= 0)
            return false;
        const top = borderThickness + p.y + (p.height - panelHeight);
        return y >= top && y <= height;
    }

    function pickerKeepOpen(x: real, y: real): bool {
        return pickerPointerBounds(x, y) || panels.windowPicker.pointerInside;
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

    onPressed: event => dragStart = Qt.point(event.x, event.y)
    onContainsMouseChanged: {
        if (!containsMouse) {
            // Only hide if not activated by shortcut
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

            if (Config.launcher.showOnHover && !launcherShortcutActive)
                visibilities.launcher = false;

            if (!windowPickerShortcutActive && (!visibilities.windowPicker || !pickerKeepOpen(mouseX, mouseY)))
                visibilities.windowPicker = false;

            if (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) {
                popouts.hasCurrent = false;
                bar.closeTray();
            }

            if (Config.bar.showOnHover)
                bar.isHovered = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;

        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);
            return;
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

        if (Config.launcher.showOnHover && launcherOpen && !launcherShortcutActive && !isOverLauncherBounds(x, y))
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

        // Show/hide bar on drag
        if (!bar.disabled && pressed && dragStart.x < bar.clampedWidth) {
            if (dragX > Config.bar.dragThreshold)
                visibilities.bar = true;
            else if (dragX < -Config.bar.dragThreshold)
                visibilities.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = pressed && dragStart.x > Math.min(width - Config.border.minThickness, bar.implicitWidth + panels.sidebar.x);

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (root.sidebarAllowedOnThisOutput && showSidebar && panels.session.offsetScale <= 0 && dragX < -Config.sidebar.dragThreshold)
                    visibilities.sidebar = true;
            } else if (root.sidebarAllowedOnThisOutput && showSidebar && dragX < -Config.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                visibilities.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                visibilities.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -Config.session.dragThreshold)
                    visibilities.session = true;
                else if (dragX > Config.session.dragThreshold)
                    visibilities.session = false;
            }

            // Hide sidebar on drag
            if (pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > Config.sidebar.dragThreshold)
                visibilities.sidebar = false;
        }

        // Bottom hover: window picker when launcher.showOnHover is off.
        if (!Config.launcher.showOnHover && !launcherOpen && !pressed && canOpenWindowPicker()) {
            if (!visibilities.windowPicker && !windowPickerDismissedSideways && inWindowPickerBottomHover(x, y))
                visibilities.windowPicker = true;
        }
        // Drag to open launcher when showOnHover is off.
        if (!Config.launcher.showOnHover && pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -Config.launcher.dragThreshold)
                visibilities.launcher = true;
            else if (dragY > Config.launcher.dragThreshold)
                visibilities.launcher = false;
        }

        // Show dashboard on hover
        const showDashboard = Config.dashboard.enabled && Config.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            visibilities.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        const showQuantumMoon = GlobalConfig.quantumMoon?.enabled !== false && GlobalConfig.quantumMoon?.showOnHover !== false && inTopPanel(panels.quantumMoonPanel, x, y);

        if (!quantumMoonShortcutActive) {
            visibilities.quantumMoon = showQuantumMoon;
        } else if (showQuantumMoon) {
            quantumMoonShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
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

        // Show utilities on hover
        const showUtilities = inBottomPanel(panels.utilities, x, y, true);

        // Always update visibility based on hover if not in shortcut mode
        if (!utilitiesShortcutActive) {
            visibilities.utilities = showUtilities;
        } else if (showUtilities) {
            // If hovering over utilities area while in shortcut mode, transition to hover control
            utilitiesShortcutActive = false;
        }

        // Bar popouts: off while launcher uses bottom hover (tray at bottom Y fought the launcher).
        if (!bar.disabled && !Config.launcher.showOnHover && !launcherOpen && x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else if (!launcherPriority && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            if (root.visibilities.launcher) {
                const inLauncherArea = root.isOverLauncherBounds(root.mouseX, root.mouseY) || root.inLauncherVerticalBand(root.mouseY);
                if (!inLauncherArea)
                    root.launcherShortcutActive = true;
            } else {
                root.launcherShortcutActive = false;
                root.dashboardShortcutActive = false;
                root.quantumMoonShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inQuantumArea = root.inTopPanel(root.panels.quantumMoonPanel, root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

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
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
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
                const inQuantumArea = root.inTopPanel(root.panels.quantumMoonPanel, root.mouseX, root.mouseY);
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
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
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
                const inPickerArea = root.pickerKeepOpen(root.mouseX, root.mouseY);
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
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        target: root.visibilities
    }
}
