pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import Caelestia.Services

Singleton {
    id: root

    property string previousSinkName: ""
    property string previousSourceName: ""

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []

    readonly property string analogSinkId: "11_00.6.analog-stereo"
    readonly property string analogPortSpeakers: "analog-output-lineout"
    readonly property string analogPortHeadphones: "analog-output-headphones"

    property string analogSinkName: ""
    property bool analogPortsAvailable: analogSinkName.length > 0
    property string analogActivePort: ""

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0

    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0

    readonly property alias cava: cava
    readonly property alias beatTracker: beatTracker

    function analogSinkNode(): PwNode {
        for (const node of sinks) {
            if (node.name && node.name.includes(analogSinkId))
                return node;
        }
        return null;
    }

    function refreshAnalogPort(): void {
        if (!analogPortsAvailable)
            return;
        refreshPortProc.running = true;
    }

    function setAnalogPort(portId: string): void {
        if (!analogPortsAvailable)
            return;

        const node = analogSinkNode();
        if (node)
            setAudioSink(node);

        setPortProc.command = ["pactl", "set-sink-port", analogSinkName, portId];
        setPortProc.running = true;
    }

    function setAnalogSpeakers(): void {
        setAnalogPort(analogPortSpeakers);
    }

    function setAnalogHeadphones(): void {
        setAnalogPort(analogPortHeadphones);
    }

    function updateAnalogSinkName(): void {
        let name = "";
        for (const node of sinks) {
            if (node.name && node.name.includes(analogSinkId)) {
                name = node.name;
                break;
            }
        }
        if (analogSinkName !== name) {
            analogSinkName = name;
            refreshAnalogPort();
        }
    }

    function setVolume(newVolume: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setSourceVolume(newVolume: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setAudioSink(newSink: PwNode): void {
        Pipewire.preferredDefaultAudioSink = newSink;
    }

    function setAudioSource(newSource: PwNode): void {
        Pipewire.preferredDefaultAudioSource = newSource;
    }

    function cycleNextAudioOutput(): void {
        if (sinks.length === 0)
            return;

        const currentIndex = sinks.findIndex(s => s === sink);
        const nextIndex = (currentIndex + 1) % sinks.length;
        setAudioSink(sinks[nextIndex]);
    }

    function setStreamVolume(stream: PwNode, newVolume: real): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = false;
            stream.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function setStreamMuted(stream: PwNode, muted: bool): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = muted;
        }
    }

    function getStreamVolume(stream: PwNode): real {
        return stream?.audio?.volume ?? 0;
    }

    function getStreamMuted(stream: PwNode): bool {
        return !!stream?.audio?.muted;
    }

    function getStreamName(stream: PwNode): string {
        if (!stream)
            return qsTr("Unknown");
        return stream.properties["application.name"] || stream.description || stream.name || qsTr("Unknown Application");
    }

    onSinkChanged: {
        if (!sink?.ready)
            return;

        refreshAnalogPort();

        const newSinkName = sink.description || sink.name || qsTr("Unknown Device");

        if (previousSinkName && previousSinkName !== newSinkName && GlobalConfig.utilities.toasts.audioOutputChanged)
            Toaster.toast(qsTr("Audio output changed"), qsTr("Now using: %1").arg(newSinkName), "volume_up");

        previousSinkName = newSinkName;
    }

    onSourceChanged: {
        if (!source?.ready)
            return;

        const newSourceName = source.description || source.name || qsTr("Unknown Device");

        if (previousSourceName && previousSourceName !== newSourceName && GlobalConfig.utilities.toasts.audioInputChanged)
            Toaster.toast(qsTr("Audio input changed"), qsTr("Now using: %1").arg(newSourceName), "mic");

        previousSourceName = newSourceName;
    }

    Component.onCompleted: {
        previousSinkName = sink?.description || sink?.name || qsTr("Unknown Device");
        previousSourceName = source?.description || source?.name || qsTr("Unknown Device");
        updateAnalogSinkName();
    }

    Connections {
        function onValuesChanged(): void {
            const newSinks = [];
            const newSources = [];
            const newStreams = [];

            for (const node of Pipewire.nodes.values) {
                if (!node.isStream) {
                    if (node.isSink)
                        newSinks.push(node);
                    else if (node.audio)
                        newSources.push(node);
                } else if (node.audio) {
                    newStreams.push(node);
                }
            }

            root.sinks = newSinks;
            root.sources = newSources;
            root.streams = newStreams;
            root.updateAnalogSinkName();
        }

        target: Pipewire.nodes
    }

    Timer {
        interval: 3000
        running: root.analogPortsAvailable
        repeat: true
        onTriggered: root.refreshAnalogPort()
    }

    Process {
        id: refreshPortProc

        command: ["sh", "-c", `pactl list sinks 2>/dev/null | awk -v sink="${root.analogSinkName}" '$1=="Name:" && $2==sink { show=1 } show && $1=="Active" && $2=="Port:" { print $3; exit }'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const port = text.trim();
                if (port === root.analogPortSpeakers)
                    root.analogActivePort = "speakers";
                else if (port === root.analogPortHeadphones)
                    root.analogActivePort = "headphones";
                else
                    root.analogActivePort = "";
            }
        }
    }

    Process {
        id: setPortProc

        onExited: refreshPortProc.running = true
    }

    PwObjectTracker {
        objects: [...root.sinks, ...root.sources, ...root.streams]
    }

    CavaProvider {
        id: cava

        bars: GlobalConfig.services.visualiserBars
    }

    BeatTracker {
        id: beatTracker
    }

    IpcHandler {
        function cycleOutput(): void {
            root.cycleNextAudioOutput();
        }

        function analogSpeakers(): void {
            root.setAnalogSpeakers();
        }

        function analogHeadphones(): void {
            root.setAnalogHeadphones();
        }

        target: "audio"
    }
}
