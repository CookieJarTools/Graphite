// A button with a word on it: outlined, or filled with the accent when it is the main thing to
// press (primary); with `danger`, its word turns red while it can be pressed (for something
// that can't be undone). `compact` is the smaller one in toasts. It presses in a little.
import QtQuick
import qs.config

Rectangle {
    id: root

    property string text
    property bool primary: false
    property bool danger: false
    property bool compact: false
    signal clicked()

    implicitWidth: label.implicitWidth + (compact ? Theme.space3 : Theme.space4) * 2
    implicitHeight: compact ? 28 : 30
    radius: compact ? Theme.radiusRow : Theme.radiusControl
    opacity: enabled ? 1 : 0.45
    color: primary ? (mouse.containsMouse ? Qt.lighter(Theme.accentFill, 1.08) : Theme.accentFill)
        : mouse.containsMouse ? Theme.hoverIcon : "transparent"
    border.color: primary ? "transparent" : danger && enabled && mouse.containsMouse ? Theme.danger : Theme.lineStrong
    border.width: 1
    scale: mouse.pressed ? Theme.grow(0.94) : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.onPressAction: root.clicked()

    UiText {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.primary ? Theme.onAccent : root.danger && root.enabled ? Theme.danger : Theme.ink
        font.weight: Theme.labelWeight
        font.pixelSize: root.compact ? Theme.hintSize : Theme.actionSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
