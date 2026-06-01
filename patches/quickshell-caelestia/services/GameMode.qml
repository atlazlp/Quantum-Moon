pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property alias enabled: props.enabled

    readonly property string resourcesScript: `${Paths.config}/scripts/game-mode-resources.sh`

    function setDynamicConfs(): void {
        Hypr.extras.applyOptions({
            "animations:enabled": 0,
            "decoration:shadow:enabled": 0,
            "decoration:blur:enabled": 0,
            "general:gaps_in": 0,
            "general:gaps_out": 0,
            "general:border_size": 1,
            "decoration:rounding": 0,
            "general:allow_tearing": 1
        });
    }

    function applyHeavyOff(): void {
        Quickshell.execDetached(["bash", root.resourcesScript, "stop"]);
    }

    function applyHeavyOn(): void {
        Quickshell.execDetached(["bash", root.resourcesScript, "start"]);
    }

    onEnabledChanged: {
        if (enabled) {
            setDynamicConfs();
            root.applyHeavyOff();
            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(qsTr("Game mode enabled"), qsTr("Disabled Hyprland animations, blur, gaps and shadows"), "gamepad");
        } else {
            Hypr.extras.message("reload");
            root.applyHeavyOn();
            if (GlobalConfig.utilities.toasts.gameModeChanged)
                Toaster.toast(qsTr("Game mode disabled"), qsTr("Hyprland settings restored"), "gamepad");
        }
    }

    function reassert(): void {
        if (!props.enabled)
            return;
        root.setDynamicConfs();
        root.applyHeavyOff();
    }

    Component.onCompleted: root.reassert()

    Timer {
        interval: 90000
        running: props.enabled
        repeat: true
        onTriggered: root.reassert()
    }

    PersistentProperties {
        id: props

        property bool enabled: Hypr.options["animations:enabled"] === 0 // qmllint disable missing-property

        reloadableId: "gameMode"
    }

    Connections {
        function onConfigReloaded(): void {
            root.reassert();
        }

        target: Hypr
    }

    IpcHandler {
        function isEnabled(): bool {
            return props.enabled;
        }

        function toggle(): void {
            props.enabled = !props.enabled;
        }

        function enable(): void {
            const was = props.enabled;
            props.enabled = true;
            if (was)
                root.applyHeavyOff();
        }

        function disable(): void {
            const was = props.enabled;
            props.enabled = false;
            if (!was)
                root.applyHeavyOn();
        }

        target: "gameMode"
    }
}
