// The desktop itself: the Graphite backdrop (BackdropGlow) on the background layer of each
// screen, under every window. No wallpaper.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.backdrop
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "graphite-backdrop"

    BackdropGlow { anchors.fill: parent }
}
