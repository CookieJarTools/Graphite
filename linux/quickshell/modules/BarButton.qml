// A square icon button, on the bar (44 px, set there) or in a panel or window (32 px): a glyph
// in the muted text colour, a tint under the pointer, a fill while active; it presses in a
// little. `label` names it for screen readers, as it has no words of its own.
import QtQuick
import qs.config

Rectangle {
    id: root

    property string glyph
    property string label
    property bool active: false
    property real glyphSize: width >= 40 ? 20 : width <= 24 ? 14 : 16
    signal clicked()

    implicitWidth: 32
    implicitHeight: 32
    radius: width >= 40 ? Theme.radiusCard : Theme.radiusRow
    color: active ? Theme.activeRow : mouse.containsMouse ? Theme.hoverIcon : "transparent"
    scale: mouse.pressed ? Theme.grow(0.94) : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.onPressAction: root.clicked()

    Glyph {
        anchors.centerIn: parent
        name: root.glyph
        implicitSize: root.glyphSize
        tint: root.active || mouse.containsMouse ? Theme.ink : Theme.inkMuted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
