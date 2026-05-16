pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screen
    required property DrawerVisibilities visibilities

    readonly property bool needsKeyboard: false
    readonly property string state: shouldBeActive ? "visible" : "hidden"

    readonly property bool cfgOn: !GlobalConfig.quantumMoon || GlobalConfig.quantumMoon.enabled !== false
    readonly property bool suppressedOnOutput: Strings.testRegexList(Config.bar.excludedScreens, screen.name)
    readonly property bool shouldBeActive: visibilities.quantumMoon && cfgOn && !suppressedOnOutput
    property real offsetScale: shouldBeActive ? 0 : 1

    readonly property string stateFile: Paths.home + "/.local/state/quantum-moon/current.json"
    readonly property string qmRootFile: Paths.home + "/.config/caelestia/quantum-moon-root"
    readonly property var planetSlugs: ["brittle-hollow", "dark-bramble", "giants-deep", "hourglass-twins", "timber-hearth"]

    readonly property real planetSize: 80
    readonly property real lockMarkerSize: 6
    readonly property real scoutLockSize: 40
    readonly property real scoutLockedBarWidth: scoutLockSize * 16 / 9
    readonly property real lockedModeLogoSize: 30
    readonly property real orbitLift: -15
    readonly property real qmCardHeightTrim: 15
    readonly property real btnSize: 52
    readonly property real arcRadius: 106
    readonly property real eyeLogoSize: 120
    readonly property real hPad: Tokens.padding.large
    readonly property real vPad: Tokens.padding.large
    readonly property real bgEdgeMargin: Tokens.padding.normal
    readonly property real contentInset: Tokens.padding.small
    readonly property real columnTopPad: 0
    readonly property real columnBottomPad: Tokens.padding.large
    readonly property real cardBottomBreathing: Tokens.padding.normal

    readonly property string selectorWheelRelPath: "/modes/SelectorWheel.png"
    readonly property real selectorWheelSize: root.btnSize * 5.8
    readonly property int selectorWheelZeroPlanetIndex: 2
    readonly property real selectorWheelDegPerPlanetIndex: 46.5
    readonly property real selectorWheelRotationOffsetDeg: 0.5
    readonly property int selectorWheelZ: -1
    readonly property int selectorWheelApplySpinDurationMs: 500

    readonly property real layoutW: arcRadius * 2 + planetSize + hPad * 2
    readonly property real layoutH: vPad * 2 + planetSize * 0.5 + arcRadius + btnSize

    readonly property bool eyeMode: root.currentSlug === "eye-of-the-universe"

    readonly property real innerContentW: layoutW + 2 * contentInset
    readonly property real innerBodyH: layoutH
    readonly property real innerBottomGap: eyeMode ? Tokens.padding.small : cardBottomBreathing
    readonly property real qmCardOuterH: root.innerBodyH + 2 * root.contentInset + root.innerBottomGap - root.qmCardHeightTrim

    property string qmRoot: ""
    property string currentSlug: ""

    implicitWidth: suppressedOnOutput ? 0 : innerContentW + 2 * bgEdgeMargin
    implicitHeight: suppressedOnOutput ? 0 : columnTopPad + root.qmCardOuterH + columnBottomPad

    width: implicitWidth
    height: implicitHeight

    visible: offsetScale < 1
    anchors.topMargin: (-implicitHeight - 5) * offsetScale
    anchors.right: parent.right
    anchors.top: parent.top

    opacity: 1 - offsetScale

    Behavior on offsetScale {
        Anim {
            type: Anim.DefaultSpatial
        }
    }

    FileView {
        path: root.qmRootFile
        watchChanges: true
        printErrors: false

        onLoaded: root.qmRoot = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.qmRoot = ""
    }

    FileView {
        path: root.stateFile
        watchChanges: true
        printErrors: false

        onLoaded: root.parseState(text())
        onFileChanged: reload()
        onLoadFailed: function (err) {
            if (err === FileViewError.FileNotFound)
                root.currentSlug = "";
        }
    }

    function parseState(data: string): void {
        try {
            const j = JSON.parse(data);
            root.currentSlug = j.slug || "";
        } catch (e) {
            root.currentSlug = "";
        }
        root.syncPersistedLockFromCurrentSlug();
    }

    function planetLogoPath(slug: string): string {
        if (!root.qmRoot.length)
            return "";
        return root.qmRoot + "/modes/" + slug + "/logo.png";
    }

    function rotationDegForPlanetIndex(i: int): real {
        if (i < 0)
            return root.selectorWheelRotationOffsetDeg;
        return (i - root.selectorWheelZeroPlanetIndex) * root.selectorWheelDegPerPlanetIndex + root.selectorWheelRotationOffsetDeg;
    }

    function rotationDegForSlug(slug: string): real {
        if (slug === "eye-of-the-universe")
            return 180;
        return root.rotationDegForPlanetIndex(root.planetSlugs.indexOf(slug));
    }

    function syncPersistedLockFromCurrentSlug(): void {
        if (QuantumMoon._lockSlugMissing && root.currentSlug.length) {
            QuantumMoon.lockedSlug = root.currentSlug;
            QuantumMoon._lockSlugMissing = false;
            if (QuantumMoon._pendingLockMarkerRoll) {
                QuantumMoon.rollLockMarker(root.scoutLockedBarWidth, root.scoutLockSize);
                QuantumMoon._pendingLockMarkerRoll = false;
                QuantumMoon.persistLockState();
            }
        }
    }

    function syncSelectorWheelDisplayIfIdle(): void {
        if (!QuantumMoon.active && !QuantumMoon.wheelRingSpinning)
            QuantumMoon.adoptWheelRingFromSlug(root.currentSlug);
    }

    readonly property string qmButtonSource: root.qmRoot.length ? root.qmRoot + "/modes/QMWhite.png" : ""
    readonly property string selectorWheelSource: root.qmRoot.length ? root.qmRoot + root.selectorWheelRelPath : ""
    readonly property string scoutSource: root.qmRoot.length ? root.qmRoot + "/modes/scout-lq.png" : ""
    readonly property string eyeLogoSource: root.qmRoot.length ? root.planetLogoPath("eye-of-the-universe") : ""

    Component.onCompleted: {
        root.syncSelectorWheelDisplayIfIdle();
        if (QuantumMoon._pendingLockMarkerRoll) {
            QuantumMoon.rollLockMarker(root.scoutLockedBarWidth, root.scoutLockSize);
            QuantumMoon._pendingLockMarkerRoll = false;
            QuantumMoon.persistLockState();
        }
        root.syncPersistedLockFromCurrentSlug();
    }

    Connections {
        target: root

        function onCurrentSlugChanged() {
            root.syncSelectorWheelDisplayIfIdle();
        }
    }

    Connections {
        target: QuantumMoon

        function onActiveChanged() {
            root.syncSelectorWheelDisplayIfIdle();
        }
    }

    Column {
        id: mainColumn

        height: root.qmCardOuterH + root.columnBottomPad
        width: root.innerContentW
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.columnTopPad
        spacing: 0

        Item {
            id: qmCard

            width: parent.width
            height: root.qmCardOuterH

            StyledRect {
                id: qmBackground

                anchors.fill: parent
                radius: Tokens.rounding.large
                color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
                clip: true

            Item {
                id: orbitLayout

                anchors.fill: parent
                anchors.leftMargin: root.contentInset
                anchors.rightMargin: root.contentInset
                anchors.topMargin: root.contentInset
                anchors.bottomMargin: root.contentInset + root.innerBottomGap
                visible: !root.eyeMode

                transform: Translate {
                    y: root.orbitLift
                }

                readonly property real arcCx: width * 0.5
                readonly property real arcCy: height - root.vPad - root.btnSize * 0.5

                Canvas {
                    id: protractorArc

                    anchors.fill: parent
                    opacity: 0.45

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35);
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.arc(orbitLayout.arcCx, orbitLayout.arcCy, root.arcRadius, Math.PI, 0, true);
                        ctx.stroke();
                    }

                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Connections {
                        target: orbitLayout

                        function onWidthChanged() {
                            protractorArc.requestPaint();
                        }

                        function onHeightChanged() {
                            protractorArc.requestPaint();
                        }
                    }

                    Connections {
                        target: root

                        function onArcRadiusChanged() {
                            protractorArc.requestPaint();
                        }
                    }
                }

                Image {
                    id: selectorWheel

                    z: root.selectorWheelZ
                    width: root.selectorWheelSize
                    height: root.selectorWheelSize
                    anchors.horizontalCenter: qmBtn.horizontalCenter
                    anchors.verticalCenter: qmBtn.verticalCenter
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: root.selectorWheelSource.length
                    source: root.selectorWheelSource
                    rotation: QuantumMoon.wheelRingDisplayDeg
                    transformOrigin: Item.Center
                }

                Repeater {
                    model: root.planetSlugs

                    delegate: Item {
                        required property string modelData
                        required property int index

                        readonly property string slug: modelData
                        readonly property real span: Math.max(1, root.planetSlugs.length - 1)
                        readonly property real angle: -Math.PI / 2 + (Math.PI * index / span)

                        width: root.planetSize
                        height: root.planetSize
                        x: orbitLayout.arcCx + root.arcRadius * Math.sin(angle) - root.planetSize * 0.5
                        y: orbitLayout.arcCy - root.arcRadius * Math.cos(angle) - root.planetSize * 0.5
                        opacity: QuantumMoon.planetLocked ? 0.38 : 1

                        Behavior on opacity {
                            Anim {
                                type: Anim.DefaultSpatial
                            }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            source: root.planetLogoPath(slug)
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !QuantumMoon.planetLocked
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                QuantumMoon.applyPlanetSlug(slug);
                            }
                        }
                    }
                }

                Image {
                    id: qmBtn

                    width: root.btnSize
                    height: root.btnSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.vPad
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    source: root.qmButtonSource
                    opacity: QuantumMoon.planetLocked ? 0.38 : 1

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: QuantumMoon.start()
                    }
                }
            }

            Item {
                id: eyeLayout

                anchors.fill: parent
                anchors.leftMargin: root.contentInset
                anchors.rightMargin: root.contentInset
                anchors.topMargin: root.contentInset
                anchors.bottomMargin: root.contentInset + root.innerBottomGap
                visible: root.eyeMode

                Image {
                    id: eyeBtn

                    width: root.eyeLogoSize
                    height: root.eyeLogoSize
                    anchors.centerIn: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    source: root.eyeLogoSource
                    opacity: QuantumMoon.planetLocked ? 0.38 : 1

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultSpatial
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: QuantumMoon.start()
                    }
                }
            }
            }

            Item {
                id: scoutLock

                z: 10000
                width: QuantumMoon.planetLocked ? root.scoutLockedBarWidth : root.scoutLockSize
                height: root.scoutLockSize
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: root.contentInset
                anchors.rightMargin: root.contentInset

                Behavior on width {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.InOutQuad
                    }
                }

                Connections {
                    target: QuantumMoon

                    function onPlanetLockedChanged() {
                        if (!QuantumMoon.planetLocked)
                            return;
                        if (!QuantumMoon.isLockMarkerPlacementValid(QuantumMoon.lockMarkerX, QuantumMoon.lockMarkerY, root.scoutLockedBarWidth, root.scoutLockSize)) {
                            QuantumMoon.rollLockMarker(root.scoutLockedBarWidth, root.scoutLockSize);
                            QuantumMoon.persistLockState();
                        }
                    }
                }

                Rectangle {
                    id: scoutHitBg

                    anchors.fill: parent
                    visible: root.qmRoot.length && (!QuantumMoon.planetLocked ? root.scoutSource.length : true)
                    color: Qt.rgba(0, 0, 0, 0.22)
                    radius: {
                        const denom = root.scoutLockedBarWidth - root.scoutLockSize;
                        const t = denom > 0.001 ? Math.max(0, Math.min(1, (scoutLock.width - root.scoutLockSize) / denom)) : 0;
                        return (1 - t) * (root.scoutLockSize * 0.5) + t * (root.scoutLockSize * 9 / 32);
                    }
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    visible: !QuantumMoon.planetLocked && root.scoutSource.length
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                    asynchronous: false
                    source: root.scoutSource
                }

                Rectangle {
                    width: root.lockMarkerSize
                    height: root.lockMarkerSize
                    radius: width * 0.5
                    color: Qt.rgba(0.62, 0.62, 0.62, 0.95)
                    visible: QuantumMoon.planetLocked && QuantumMoon.lockedSlug.length > 0
                        && QuantumMoon.isLockMarkerPlacementValid(QuantumMoon.lockMarkerX, QuantumMoon.lockMarkerY, root.scoutLockedBarWidth, root.scoutLockSize)
                    x: QuantumMoon.lockMarkerX
                    y: QuantumMoon.lockMarkerY
                }

                Item {
                    id: lockedPlanetThumb

                    width: root.lockedModeLogoSize
                    height: root.lockedModeLogoSize
                    anchors.centerIn: parent
                    visible: QuantumMoon.planetLocked && QuantumMoon.lockedSlug.length > 0

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: false
                        source: root.planetLogoPath(QuantumMoon.lockedSlug)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (QuantumMoon.planetLocked)
                            QuantumMoon.releaseLock();
                        else if (root.currentSlug.length)
                            QuantumMoon.engageLock(root.currentSlug, root.scoutLockedBarWidth, root.scoutLockSize);
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: root.columnBottomPad
        }
    }
}
