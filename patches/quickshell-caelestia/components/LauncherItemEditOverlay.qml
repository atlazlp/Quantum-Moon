pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils

FocusScope {
    id: root

    required property string screenName
    required property var visibilities

    readonly property var target: LauncherItemOverrides.editTarget
    readonly property bool open: LauncherItemOverrides.editOpen && LauncherItemOverrides.editScreen === root.screenName

    property string draftLabel: ""
    property string draftSubtitle: ""
    property string pendingIconPath: ""
    property string previewIcon: ""

    visible: open || closing
    enabled: open && !closing
    z: 1_000_000

    property bool closing: false
    property bool targetChangedDuringClose: false

    onTargetChanged: {
        if (closing && target !== null)
            targetChangedDuringClose = true;
    }

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
        targetChangedDuringClose = false;
        closeAnim.start();
    }

    function applyDraft(): void {
        const t = target;
        if (!t)
            return;
        const ok = LauncherItemOverrides.saveOverride(t.type, t.key, draftLabel, draftSubtitle, pendingIconPath);
        if (!ok && pendingIconPath) {
            Toaster.toast(qsTr("Could not save icon"), qsTr("Copying the image failed"), "error");
            return;
        }
        dismiss();
    }

    function resetEntry(): void {
        const t = target;
        if (!t)
            return;
        LauncherItemOverrides.resetOverride(t.type, t.key);
        dismiss();
    }

    onOpenChanged: {
        if (open) {
            closing = false;
            const t = target;
            draftLabel = LauncherItemOverrides.displayLabel(t.type, t.key, t.defaultLabel ?? "");
            draftSubtitle = LauncherItemOverrides.subtitle(t.type, t.key, t.defaultSubtitle ?? "");
            labelField.text = draftLabel;
            subtitleField.text = draftSubtitle;
            pendingIconPath = "";
            previewIcon = LauncherItemOverrides.iconSource(t.type, t.key, t.defaultIcon ?? "");
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
            if (root.targetChangedDuringClose) {
                root.targetChangedDuringClose = false;
                const t = root.target;
                if (t) {
                    root.draftLabel = LauncherItemOverrides.displayLabel(t.type, t.key, t.defaultLabel ?? "");
                    root.draftSubtitle = LauncherItemOverrides.subtitle(t.type, t.key, t.defaultSubtitle ?? "");
                    labelField.text = root.draftLabel;
                    subtitleField.text = root.draftSubtitle;
                    root.pendingIconPath = "";
                    root.previewIcon = LauncherItemOverrides.iconSource(t.type, t.key, t.defaultIcon ?? "");
                }
                backdrop.opacity = 1;
                card.opacity = 1;
                card.scale = 1;
                root.reclaimTimer.start();
                Qt.callLater(() => {
                    root.forceActiveFocus();
                    root.reclaimFocusIfNeeded();
                });
            } else {
                LauncherItemOverrides.closeEditor();
            }
        }
    }

    Keys.onEscapePressed: dismiss()
    Keys.priority: Keys.BeforeItem
    focus: open && !closing

    FileDialog {
        id: iconPicker

        title: qsTr("Choose launcher icon")
        filterLabel: qsTr("Image files")
        filters: Images.validImageExtensions
        onAccepted: path => {
            pendingIconPath = path;
            previewIcon = Qt.resolvedUrl(path);
        }
    }

    StyledRect {
        id: backdrop

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.5)
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
        readonly property int pad: Tokens.padding.large
        implicitWidth: Math.min(parent.width - pad * 2, 460)
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

        ColumnLayout {
            id: cardColumn

            anchors.fill: parent
            anchors.margins: card.pad
            spacing: Tokens.spacing.normal

            StyledText {
                Layout.fillWidth: true
                text: root.target?.type === "window" ? qsTr("Edit window entry") : qsTr("Edit launcher entry")
                font.pointSize: Tokens.font.size.large
                font.weight: 500
            }

            StyledText {
                Layout.fillWidth: true
                text: root.target?.key ?? ""
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.normal

                StyledRect {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    radius: Tokens.rounding.normal
                    color: Colours.layer(Colours.palette.m3surfaceContainer, 1)

                    IconImage {
                        anchors.centerIn: parent
                        asynchronous: true
                        source: root.previewIcon
                        implicitSize: 56
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        Layout.fillWidth: true
                        implicitHeight: uploadBtnRow.implicitHeight + Tokens.padding.normal * 2
                        radius: Tokens.rounding.full
                        color: Colours.layer(Colours.palette.m3secondaryContainer, 1)

                        Row {
                            id: uploadBtnRow

                            anchors.centerIn: parent
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "upload"
                                color: Colours.palette.m3onSecondaryContainer
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("Upload icon")
                                color: Colours.palette.m3onSecondaryContainer
                            }
                        }

                        StateLayer {
                            radius: parent.radius
                            onClicked: iconPicker.open()
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("Recommended: 128×128 px, square PNG or WebP")
                        font.pointSize: Tokens.font.size.small
                        color: Colours.palette.m3outline
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Display name")
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
            }

            StyledTextField {
                id: labelField

                Layout.fillWidth: true
                text: root.draftLabel
                placeholderText: root.target?.defaultLabel ?? ""
                onTextChanged: root.draftLabel = text
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Subtitle")
                font.pointSize: Tokens.font.size.small
                color: Colours.palette.m3outline
            }

            StyledTextField {
                id: subtitleField

                Layout.fillWidth: true
                text: root.draftSubtitle
                placeholderText: root.target?.defaultSubtitle ?? ""
                onTextChanged: root.draftSubtitle = text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.normal

                Item {
                    Layout.fillWidth: true
                }

                StyledRect {
                    implicitWidth: resetBtn.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: resetBtn.implicitHeight + Tokens.padding.normal * 2
                    radius: Tokens.rounding.full
                    color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 1)

                    StyledText {
                        id: resetBtn

                        anchors.centerIn: parent
                        text: qsTr("Reset")
                    }

                    StateLayer {
                        radius: parent.radius
                        onClicked: root.resetEntry()
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
                    }

                    StateLayer {
                        radius: parent.radius
                        onClicked: root.dismiss()
                    }
                }

                StyledRect {
                    implicitWidth: saveBtn.implicitWidth + Tokens.padding.large * 2
                    implicitHeight: saveBtn.implicitHeight + Tokens.padding.normal * 2
                    radius: Tokens.rounding.full
                    color: Colours.palette.m3primary

                    StyledText {
                        id: saveBtn

                        anchors.centerIn: parent
                        text: qsTr("Save")
                        color: Colours.palette.m3onPrimary
                    }

                    StateLayer {
                        radius: parent.radius
                        color: Colours.palette.m3onPrimary
                        onClicked: root.applyDraft()
                    }
                }
            }
        }
    }
}
