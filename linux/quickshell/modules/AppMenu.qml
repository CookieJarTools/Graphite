// An app's right-click menu on the bar, over the app: open another window, pin or unpin it,
// close its windows.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property string screenName
    property var barWindow: null

    readonly property var group: ShellState.appMenu
    readonly property bool open: group !== null && ShellState.appMenuScreen === screenName

    visible: open
    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: Theme.space2
        left: Math.max(Theme.space2, ShellState.appMenuX - implicitWidth / 2)
    }
    exclusiveZone: 0
    implicitWidth: 220
    implicitHeight: rows.implicitHeight + Theme.space1 * 2
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "graphite-menu"

    HyprlandFocusGrab {
        windows: root.barWindow ? [root, root.barWindow] : [root]
        active: root.open
        onCleared: ShellState.closePanels()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1

        ColumnLayout {
            id: rows
            anchors.fill: parent
            anchors.margins: Theme.space1
            spacing: 0

            MenuRow {
                Layout.fillWidth: true
                visible: root.group !== null && root.group.entry !== null
                text: "New window"
                onClicked: {
                    Apps.launch(root.group.entry);
                    ShellState.closePanels();
                }
            }

            MenuRow {
                Layout.fillWidth: true
                visible: root.group !== null && root.group.entry !== null
                text: root.group && root.group.pinned ? "Unpin from taskbar" : "Pin to taskbar"
                onClicked: {
                    Apps.setPinned(root.group.key, !root.group.pinned);
                    ShellState.closePanels();
                }
            }

            MenuRow {
                Layout.fillWidth: true
                visible: root.group !== null && root.group.windows.length > 0
                text: root.group && root.group.windows.length > 1 ? "Close all " + root.group.windows.length + " windows" : "Close window"
                onClicked: {
                    for (const window of root.group.windows) window.close();
                    ShellState.closePanels();
                }
            }
        }
    }
}
