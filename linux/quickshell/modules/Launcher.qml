// The launcher (the Super key) and the compact search (Alt+Space): LauncherView in a 560 px
// panel 190 px from the top, over a dimmed screen, on the screen with the focused window. It
// drops in from 8 px above, growing from 98%; Escape or a click outside closes it.
import QtQuick
import QtQuick.Effects
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
        Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durationScrim : Theme.durationFast } }

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.closeLaunchers()
        }
    }

    RectangularShadow {
        anchors.fill: card
        opacity: card.opacity
        scale: card.scale
        transform: Translate { y: drop.y }
        offset.y: 32
        blur: 80
        spread: -12
        radius: card.radius
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.6 : 0.2)
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.min(Theme.launcherTop, parent.height * 0.18)
        width: Math.min(Theme.launcherWidth, parent.width - Theme.space4 * 2)
        height: Math.min(root.palette ? 440 : 600, parent.height - y - Theme.space10)
        radius: Theme.radiusLg
        color: Theme.glass(Theme.panel, 0.96)
        border.color: Theme.border
        border.width: 1
        clip: true
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : Theme.grow(0.98)
        transform: Translate {
            id: drop
            y: root.open ? 0 : -Theme.rise
            Behavior on y { NumberAnimation { duration: root.open ? Theme.durationLauncherIn : Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeOut : Theme.easeIn } }
        }
        Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durationLauncherIn : Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeOut : Theme.easeIn } }
        Behavior on scale { NumberAnimation { duration: root.open ? Theme.durationLauncherIn : Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeOut : Theme.easeIn } }

        MouseArea { anchors.fill: parent } // clicks on the card stay on it

        LauncherView {
            id: view
            anchors.fill: parent
            mode: root.palette ? "palette" : "launcher"
            onDone: ShellState.closeLaunchers()
        }
    }
}
