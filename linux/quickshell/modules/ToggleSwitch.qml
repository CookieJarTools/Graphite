// An on/off switch; a click flips it (toggled() asks the owner to change `on`).
import QtQuick
import qs.config

Rectangle {
    id: root

    property bool on: false
    signal toggled()

    implicitWidth: 40
    implicitHeight: 22
    radius: 11
    opacity: enabled ? 1 : 0.45
    color: on ? Theme.accent : Theme.surface100
    border.color: on ? Theme.accent : Theme.lineStrong
    border.width: 1
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 3
        x: root.on ? root.width - width - 3 : 3
        color: root.on ? Theme.onAccent : Theme.inkMuted
        Behavior on x { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeStandard } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
