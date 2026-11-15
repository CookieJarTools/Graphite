// A thin slider: a 4 px track that fills up to the value (0 to 1), in the accent, or in the
// text colour with `light` (quick settings); dragging, a click or the wheel moves it.
import QtQuick
import qs.config

Item {
    id: root

    property real value: 0
    property bool dimmed: false
    property bool light: false
    signal moved(real value)

    implicitHeight: 24

    Accessible.role: Accessible.Slider

    function setFrom(x) {
        root.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.track

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: 2
            color: root.dimmed ? Theme.inkFaint : root.light ? Theme.ink : Theme.accent
        }
    }

    Rectangle {
        x: track.width * Math.max(0, Math.min(1, root.value)) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: "#ffffff"
        border.color: Theme.tint("#000000", 0.25)
        border.width: 1
        scale: mouse.containsMouse || mouse.pressed ? Theme.grow(1.15) : 1
        Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onPressed: event => root.setFrom(event.x)
        onPositionChanged: event => { if (pressed) root.setFrom(event.x); }
        onWheel: event => root.moved(Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.02 : -0.02))))
    }
}
