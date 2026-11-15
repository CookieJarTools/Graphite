// Notification pop-ups, stacked in the top-right corner of the focused screen, 16 px in, the
// newest at the bottom. The window keeps one height, room for the most toasts there can be
// and their shadows: grown or shrunk as toasts came and went, Hyprland stretched what was
// showing for a frame. Only the toasts take the pointer.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    screen: {
        const focused = Hyprland.focusedMonitor;
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => focused && candidate.name === focused.name) || screens[0];
    }
    visible: Notifs.popups.length > 0
    anchors {
        top: true
        right: true
    }
    exclusiveZone: 0
    readonly property real shadowRoom: 40
    implicitWidth: Theme.toastWidth + Theme.space4 + shadowRoom
    implicitHeight: Math.min(screen ? screen.height - Theme.barTop : 900, 900)
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-toasts"
    mask: Region { item: stack }

    property var shown: ({})

    ColumnLayout {
        id: stack

        x: root.shadowRoom
        y: Theme.space4
        width: Theme.toastWidth
        spacing: 10

        // A ScriptModel keeps the toasts already up as they are when one comes or goes
        // (rebuilt whole, each was made again, its icon and its wait starting over).
        Repeater {
            model: ScriptModel { values: Notifs.popups.slice().reverse() }

            Toast {
                Layout.fillWidth: true
                gap: stack.spacing
                // Only a notification not shown before slides in.
                fresh: {
                    const id = modelData.notification ? modelData.notification.id : -1;
                    const seen = root.shown[id] === true;
                    root.shown[id] = true;
                    return !seen;
                }
            }
        }
    }
}
