// A thin slider: the track fills with the accent up to the value (0 to 1); dragging, a click
// or the wheel moves it.
import QtQuick
import qs.config

Item {
    id: root

    property real value: 0
    property bool dimmed: false
    signal moved(real value)

    implicitHeight: 24

    function setFrom(x) {
        root.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.surface300

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            radius: 2
            color: root.dimmed ? Theme.inkMuted : Theme.accent
        }
    }

    Rectangle {
        x: track.width * Math.max(0, Math.min(1, root.value)) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        radius: 8
        color: Theme.ink
        border.color: Theme.surface200
        border.width: 3
        scale: mouse.containsMouse || mouse.pressed ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: Theme.durationInstant } }
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
