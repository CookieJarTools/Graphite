// A quick-settings tile: a glyph, a name and a line of detail; filled with the accent while on.
import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root

    property string glyph
    property string label
    property string detail
    property bool on: false
    property bool available: true
    signal toggled()

    implicitHeight: 56
    radius: Theme.radiusMd
    color: on ? Theme.accent : (mouse.containsMouse ? Theme.surface300 : Theme.surface100)
    border.color: on ? Theme.accent : Theme.line
    border.width: 1
    opacity: available ? 1 : 0.5
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        spacing: Theme.space3

        Glyph { name: root.glyph }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            UiText {
                Layout.fillWidth: true
                text: root.label
                font.weight: Font.DemiBold
                color: root.on ? Theme.onAccent : Theme.ink
            }

            UiText {
                Layout.fillWidth: true
                text: root.detail
                font.pixelSize: Theme.hintSize
                color: root.on ? Theme.onAccent : Theme.inkMuted
                opacity: root.on ? 0.8 : 1
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        onClicked: root.toggled()
    }
}
