// The launcher (the Super key) and the compact search (Alt+Space): LauncherView in a card over
// a dimmed screen, on the screen with the focused window. Escape or a click outside closes.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    readonly property bool open: ShellState.launcherOpen || ShellState.paletteOpen
    readonly property bool palette: ShellState.paletteOpen

    screen: {
        const focused = Hyprland.focusedMonitor;
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => focused && candidate.name === focused.name) || screens[0];
    }
    visible: open || card.opacity > 0
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-launcher"
    WlrLayershell.keyboardFocus: open && ShellState.menu === null ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: if (open) view.reset()
    onPaletteChanged: if (open) view.reset()

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durationBase : Theme.durationFast } }

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.closeLaunchers()
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * (root.palette ? 0.2 : 0.14)
        width: Math.min(root.palette ? 640 : Theme.launcherWidth, parent.width - Theme.space4 * 2)
        height: Math.min(root.palette ? 440 : 600, parent.height - y - Theme.space10)
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1
        clip: true
        opacity: root.open ? 1 : 0
        transform: Translate {
            y: root.open ? 0 : Theme.rise
            Behavior on y { NumberAnimation { duration: root.open ? 220 : 140; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeEnter : Theme.easeExit } }
        }
        Behavior on opacity { NumberAnimation { duration: root.open ? 220 : 140; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeEnter : Theme.easeExit } }

        MouseArea { anchors.fill: parent } // clicks on the card stay on it

        LauncherView {
            id: view
            anchors.fill: parent
            mode: root.palette ? "palette" : "launcher"
            onDone: ShellState.closeLaunchers()
        }
    }
}
