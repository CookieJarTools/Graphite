// One row of a small menu (an app's right-click menu on the bar).
import QtQuick
import qs.config

Rectangle {
    id: root

    property string text
    signal clicked()

    implicitWidth: label.implicitWidth + Theme.space3 * 2
    implicitHeight: 32
    radius: Theme.radiusSm
    color: mouse.containsMouse ? Theme.surface300 : "transparent"

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
