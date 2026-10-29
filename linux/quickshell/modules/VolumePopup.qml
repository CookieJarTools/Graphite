// The volume, changed by the mouse's side scroll (tilting the wheel) and the keyboard's volume
// keys (hyprland.lua binds them to these shortcuts), shown for a moment in a small pill over
// the bar, as Windows does. `qs -c graphite ipc call volume up|down|mute` does the same.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import qs.config
import qs.services

Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property real step: 0.02
    property bool showing: false

    PwObjectTracker { objects: [root.sink] }

    function change(by) {
        if (!sink || !sink.audio) return;
        sink.audio.volume = Math.max(0, Math.min(1, Math.round((volume + by) * 100) / 100));
        if (by > 0) sink.audio.muted = false;
        show();
    }

    function toggleMute() {
        if (!sink || !sink.audio) return;
        sink.audio.muted = !sink.audio.muted;
        show();
    }

    function show() {
        showing = true;
        hide.restart();
    }

    Timer {
        id: hide
        interval: 1500
        onTriggered: root.showing = false
    }

    GlobalShortcut { name: "volume-up"; description: "Turn the volume up"; onPressed: root.change(root.step) }
    GlobalShortcut { name: "volume-down"; description: "Turn the volume down"; onPressed: root.change(-root.step) }
    GlobalShortcut { name: "volume-mute"; description: "Mute or unmute"; onPressed: root.toggleMute() }

    IpcHandler {
        target: "volume"

        function up(): void { root.change(root.step); }
        function down(): void { root.change(-root.step); }
        function mute(): void { root.toggleMute(); }
    }

    PanelWindow {
        visible: root.showing || card.opacity > 0
        screen: Quickshell.screens.find(screen => Hyprland.focusedMonitor && screen.name === Hyprland.focusedMonitor.name) || Quickshell.screens[0]
        anchors.bottom: true
        margins.bottom: 72
        implicitWidth: card.width
        implicitHeight: card.height
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-panel-volume"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: card
            width: content.implicitWidth + Theme.space4 * 2
            height: 44
            radius: 22
            color: Theme.surface200
            border.color: Theme.glassEdge
            border.width: 1
            opacity: root.showing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

            RowLayout {
                id: content
                anchors.centerIn: parent
                spacing: Theme.space3

                Glyph {
                    name: root.muted || root.volume === 0 ? "audio-volume-muted-symbolic"
                        : root.volume < 0.34 ? "audio-volume-low-symbolic"
                        : root.volume < 0.67 ? "audio-volume-medium-symbolic" : "audio-volume-high-symbolic"
                }

                Rectangle {
                    implicitWidth: 160
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surface300

                    Rectangle {
                        width: parent.width * (root.muted ? 0 : root.volume)
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: Theme.durationInstant } }
                    }
                }

                UiText {
                    Layout.preferredWidth: 34
                    text: root.muted ? "Off" : Math.round(root.volume * 100)
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }
            }
        }
    }
}
