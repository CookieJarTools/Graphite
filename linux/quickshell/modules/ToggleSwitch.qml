// An on/off switch: a 36 x 20 track, the accent while on, with a white knob that slides across;
// a click flips it (toggled() asks the owner to change `on`).
import QtQuick
import qs.config

Rectangle {
    id: root

    property bool on: false
    signal toggled()

    implicitWidth: 36
    implicitHeight: 20
    radius: 10
    opacity: enabled ? 1 : 0.45
    color: on ? Theme.accent : Theme.switchOff
    Behavior on color { ColorAnimation { duration: Theme.durationKnob; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: on
    Accessible.onToggleAction: root.toggled()
    Accessible.onPressAction: root.toggled()

    Rectangle {
        width: 16
        height: 16
        radius: 8
        y: 2
        x: root.on ? root.width - width - 2 : 2
        color: "#ffffff"
        Behavior on x { NumberAnimation { duration: Theme.durationKnob; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSpring } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
