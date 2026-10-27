// A square button on the bar or in a panel: a glyph, a hover fill, and a fill while active.
import QtQuick
import qs.config

Rectangle {
    id: root

    property string glyph
    property bool active: false
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    radius: Theme.radiusSm
    color: mouse.containsMouse || active ? Theme.surface300 : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    Glyph {
        anchors.centerIn: parent
        name: root.glyph
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
