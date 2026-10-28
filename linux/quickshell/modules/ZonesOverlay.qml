// The zones over a screen while a window is dragged with Shift held (Zones.qml): each zone
// numbered, the ones the window will fill in the accent. It takes no input; the drag goes on
// underneath.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property bool open: Zones.showing && monitor !== null && Zones.monitorName === monitor.name && Zones.area !== null

    visible: open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-zones"

    Repeater {
        model: root.open ? Zones.zones : []

        Rectangle {
            id: zone

            required property var modelData
            required property int index
            readonly property var rect: Zones.zoneRect(modelData, Zones.area)
            readonly property bool picked: Zones.selection.includes(index)

            x: rect.x - (root.monitor ? root.monitor.x : 0)
            y: rect.y - (root.monitor ? root.monitor.y : 0)
            width: rect.width
            height: rect.height
            radius: Theme.radiusLg
            color: picked ? Zones.alpha(Theme.accent, 0.28) : Zones.alpha(Theme.surface200, 0.55)
            border.color: picked ? Theme.accent : Theme.glassEdge
            border.width: picked ? 2 : 1
            Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

            UiText {
                anchors.centerIn: parent
                text: zone.index + 1
                font.pixelSize: 40
                font.weight: Font.DemiBold
                color: zone.picked ? Theme.accent : Theme.inkMuted
                opacity: 0.8
            }
        }
    }
}
