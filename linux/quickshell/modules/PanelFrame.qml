// A panel that opens from the bar: a card (radius 14, 14 px in) over a blur, above it, either
// lined up with the bar's right end (rightInset) or centred over a point on it (centreX). It
// rises in and sinks away. It takes the keyboard while open (Escape closes it) and closes on
// a click anywhere else.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: frame

    required property string name          // ShellState.panel while this one shows
    required property string screenName
    property var barWindow: null
    property real panelWidth: 300
    property real rightInset: -1
    property real centreX: -1
    default property alias content: column.data

    readonly property bool open: ShellState.panel === name && ShellState.panelScreen === screenName

    visible: open || card.opacity > 0
    anchors {
        bottom: true
        right: rightInset >= 0
        left: rightInset < 0
    }
    // Just above the bar's strip (the bar and a gap on each side of it), placed directly rather
    // than above the space the bar reserves: an auto-hiding bar reserves none, and the panel
    // then covered the bar.
    margins {
        bottom: Theme.barTop + Theme.space2
        right: Math.max(0, rightInset)
        left: Math.max(Theme.space2, centreX - implicitWidth / 2)
    }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: panelWidth
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "graphite-panel"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // A click outside the panel and the bar closes it (a click on the bar toggles it itself).
    HyprlandFocusGrab {
        windows: frame.barWindow ? [frame, frame.barWindow] : [frame]
        active: frame.open
        onCleared: ShellState.closePanels()
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: column.implicitHeight + 14 * 2
        radius: Theme.radiusLg
        color: Theme.glass(Theme.panel, 0.94)
        border.color: Theme.border
        border.width: 1
        opacity: frame.open ? 1 : 0
        transform: Translate {
            y: frame.open ? 0 : Theme.rise
            Behavior on y {
                NumberAnimation {
                    duration: frame.open ? Theme.durationBase : Theme.durationFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: frame.open ? Theme.easeOut : Theme.easeIn
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: frame.open ? Theme.durationBase : Theme.durationFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: frame.open ? Theme.easeOut : Theme.easeIn
            }
        }

        FocusScope {
            anchors.fill: parent
            focus: frame.open
            Keys.onEscapePressed: ShellState.closePanels()

            ColumnLayout {
                id: column
                anchors.fill: parent
                anchors.margins: 14
                spacing: Theme.space3
            }
        }
    }
}
