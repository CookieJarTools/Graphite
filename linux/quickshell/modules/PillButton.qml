// A button with a word on it: filled with the accent when it is the main thing to press
// (primary), or red for something that can't be undone (danger).
import QtQuick
import qs.config

Rectangle {
    id: root

    property string text
    property bool primary: false
    property bool danger: false
    signal clicked()

    implicitWidth: label.implicitWidth + Theme.space4 * 2
    implicitHeight: 32
    radius: Theme.radiusSm
    opacity: enabled ? 1 : 0.45
    color: primary ? (mouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
        : mouse.containsMouse ? Theme.surface300 : Theme.surface100
    border.color: primary ? Theme.accent : danger && mouse.containsMouse ? Theme.danger : Theme.line
    border.width: 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    UiText {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.primary ? Theme.onAccent : root.danger ? Theme.danger : Theme.ink
        font.weight: Font.DemiBold
        font.pixelSize: Theme.actionSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
