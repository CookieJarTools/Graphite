// One row of a small menu, or a quiet text button: 30 px, a tint under the pointer.
import QtQuick
import qs.config

Rectangle {
    id: root

    property string text
    signal clicked()

    implicitWidth: label.implicitWidth + Theme.space3 * 2
    implicitHeight: 30
    radius: Theme.radiusSm
    color: mouse.containsMouse ? Theme.hoverIcon : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: root.clicked()

    UiText {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        x: Theme.space3
        text: root.text
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
