// The network and volume glyphs on the bar; opens quick settings.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import qs.config

Rectangle {
    id: root

    property bool active: false
    signal clicked()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    implicitWidth: glyphs.implicitWidth + Theme.space3 * 2
    implicitHeight: 36
    radius: Theme.radiusSm
    color: mouse.containsMouse || active ? Theme.surface300 : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    RowLayout {
        id: glyphs
        anchors.centerIn: parent
        spacing: Theme.space3

        Glyph { name: "network-wireless-signal-excellent-symbolic" }
        Glyph { name: root.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic" }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
