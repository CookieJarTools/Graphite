// The network, volume and (with a real battery) battery glyphs on the bar; opens quick
// settings. The network glyph dims while offline.
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.config
import qs.services

Rectangle {
    id: root

    property bool active: false
    signal clicked()

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent

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

        Glyph {
            name: Network.wired && !Network.wifiEnabled ? "network-wired-symbolic" : "network-wireless-signal-excellent-symbolic"
            opacity: Network.online ? 1 : 0.4
        }
        Glyph { name: root.muted ? "audio-volume-muted-symbolic" : "audio-volume-high-symbolic" }
        Glyph {
            visible: root.hasBattery
            name: root.battery ? (root.battery.iconName || "battery-good-symbolic") : ""
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
