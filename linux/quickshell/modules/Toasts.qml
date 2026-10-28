// Notification pop-ups, stacked down from the top-right corner of the focused screen.
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
    margins {
        top: Theme.space4
        right: Theme.space4
    }
    exclusiveZone: 0
    implicitWidth: Theme.toastWidth
    implicitHeight: stack.implicitHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-toasts"

    property var shown: ({})

    ColumnLayout {
        id: stack

        width: parent.width
        spacing: Theme.space2

        Repeater {
            model: Notifs.popups

            Toast {
                Layout.fillWidth: true
                // Only a notification not shown before slides in (the list is rebuilt whole).
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
