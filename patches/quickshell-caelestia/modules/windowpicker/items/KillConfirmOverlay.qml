pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services

FocusScope {
    id: root

    required property var target
    required property var visibilities

    signal dismissed()

    readonly property bool open: root.target !== null && root.target !== undefined

    visible: open || closing
    enabled: open && !closing
    z: 1_000_000

    property bool closing: false

    function containsDescendant(ancestor: Item, item: Item): bool {
        let p = item;
        while (p) {
            if (p === ancestor)
                return true;
            p = p.parent;
        }
        return false;
    }

    function reclaimFocusIfNeeded(): void {
        if (!open || closing)
            return;
        const win = Window.window;
        if (!win)
            return;
        const fi = win.activeFocusItem;
        if (!fi || !containsDescendant(root, fi))
            root.forceActiveFocus();
    }

    function dismiss(): void {
        if (!open || closing)
            return;
        closing = true;
        closeAnim.start();
    }

    function confirmKill(): void {
        const row = root.target;
        if (!row)
            return;

        const addr = (row.address ?? "").toString().trim();
        const pid = row.pid ?? 0;
        if (addr)
            Hypr.dispatch(`killwindow address:${addr}`);
        else if (pid > 0)
            killProc.command = ["kill", "-TERM", String(pid)];
        else
            return;

        if (addr)
            Hyprland.refreshToplevels();
        else
            killProc.running = true;

        dismiss();
    }

    function handleKey(event: var): void {
        if (!open || closing)
            return;

        const key = event.key;
        const text = event.text?.toLowerCase() ?? "";

        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Y || text === "y") {
            event.accepted = true;
            confirmKill();
        } else if (key === Qt.Key_Escape || key === Qt.Key_N || key === Qt.Key_C || text === "n" || text === "c") {
            event.accepted = true;
            dismiss();
        }
    }

    onOpenChanged: {
        if (open) {
            closing = false;
            reclaimTimer.start();
            Qt.callLater(() => {
                root.forceActiveFocus();
                root.reclaimFocusIfNeeded();
            });
        } else {
            reclaimTimer.stop();
        }
    }

    Timer {
        id: reclaimTimer
        interval: 50
        repeat: true
        running: false
        onTriggered: root.reclaimFocusIfNeeded()
    }

    Shortcut {
        enabled: root.open && !root.closing
        context: Qt.ApplicationShortcut
        sequences: ["Return", "Enter"]
        onActivated: root.confirmKill()
    }

    Shortcut {
        enabled: root.open && !root.closing
        context: Qt.ApplicationShortcut
        sequence: "Escape"
        onActivated: root.dismiss()
    }

    ParallelAnimation {
        id: closeAnim

        Anim {
            target: backdrop
            property: "opacity"
            to: 0
        }

        Anim {
            target: card
            property: "opacity"
            to: 0
        }

        Anim {
            target: card
            property: "scale"
            to: 0.92
        }

        onFinished: {
            root.closing = false;
            root.dismissed();
        }
    }

    Process {
        id: killProc

        onExited: Hyprland.refreshToplevels()
    }

    Keys.onPressed: event => root.handleKey(event)
    Keys.onReturnPressed: confirmKill()
    Keys.onEnterPressed: confirmKill()
    Keys.onEscapePressed: dismiss()
    Keys.priority: Keys.BeforeItem

    focus: open && !closing

    StyledRect {
        id: backdrop

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        opacity: open && !closing ? 1 : 0

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: mouse => {
                mouse.accepted = true;
                root.dismiss();
            }
        }
    }

    StyledRect {
        id: card

        z: 1
        anchors.centerIn: parent
        implicitWidth: Math.min(parent.width - pad * 2, 420)
        readonly property int pad: Tokens.padding.large
        implicitHeight: cardColumn.implicitHeight + pad * 2

        radius: Tokens.rounding.large
        color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
        opacity: open && !closing ? 1 : 0
        scale: open && !closing ? 1 : 0.92

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.StandardSmall
            }
        }

        Column {
            id: cardColumn

            anchors.centerIn: parent
            width: parent.width - card.pad * 2
            spacing: Tokens.spacing.normal

            StyledText {
                width: parent.width
                text: qsTr("End process?")
                font.pointSize: Tokens.font.size.large
                font.weight: 500
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                width: parent.width
                text: root.target?.line ?? ""
                font.pointSize: Tokens.font.size.normal
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: {
                    const pid = root.target?.pid ?? 0;
                    return pid > 0 ? qsTr("PID %1").arg(pid) : qsTr("Window %1").arg((root.target?.address ?? "").replace(/^0x/i, ""));
                }
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                horizontalAlignment: Text.AlignHCenter
            }

            StyledText {
                width: parent.width
                text: qsTr("Enter or Y to kill · N or C to cancel")
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacing.normal

                StyledRect {
                    implicitWidth: killBtn.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: killBtn.implicitHeight + Tokens.padding.normal * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3error

                    StyledText {
                        id: killBtn

                        anchors.centerIn: parent
                        text: qsTr("Kill")
                        color: Colours.palette.m3onError
                        font.pointSize: Tokens.font.size.normal
                    }

                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onError
                        onClicked: root.confirmKill()
                    }
                }

                StyledRect {
                    implicitWidth: cancelBtn.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: cancelBtn.implicitHeight + Tokens.padding.normal * 2
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)

                    StyledText {
                        id: cancelBtn

                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        font.pointSize: Tokens.font.size.normal
                    }

                    StateLayer {
                        radius: parent.radius
                        onClicked: root.dismiss()
                    }
                }
            }
        }
    }
}
