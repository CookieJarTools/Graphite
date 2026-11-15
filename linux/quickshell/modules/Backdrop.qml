// The desktop itself: the wallpaper (BackdropGlow) on the background layer of each screen,
// under every window, with the lock screen's stronger glow. No desktop icons. The live
// wallpaper (Personalisation) moves only while nothing covers it: no window on the screen's
// workspace, not locked, and window animations on.
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

    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property var workspace: monitor ? monitor.activeWorkspace : null
    readonly property bool empty: workspace !== null && Array.from(workspace.toplevels.values).length === 0

    BackdropGlow {
        anchors.fill: parent
        strength: Theme.dark ? 0.3 : 0.16
        live: Look.liveWallpaper && root.empty && !ShellState.locked && !Theme.reducedMotion
    }
}
