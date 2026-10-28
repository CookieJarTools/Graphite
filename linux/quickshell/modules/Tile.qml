// A quick-settings tile: a glyph, a name and a line of detail; filled with the accent while on.
// A click on it switches it; with `more`, its right end (an arrow) opens its list instead
// (networks, devices), as on Windows.
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
    property bool more: false
    signal toggled()
    signal moreClicked()

    implicitHeight: 56
    radius: Theme.radiusMd
    color: on ? Theme.accent : (mouse.containsMouse ? Theme.surface300 : Theme.surface100)
    border.color: on ? Theme.accent : Theme.line
    border.width: 1
    opacity: available ? 1 : 0.5
    clip: true
    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        onClicked: root.toggled()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        spacing: Theme.space3

        Glyph {
            name: root.glyph
            tint: root.on ? Theme.onAccent : Theme.ink
        }

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

        // The way into the tile's list.
        Rectangle {
            visible: root.more
            Layout.fillHeight: true
            implicitWidth: 36
            color: moreMouse.containsMouse ? (root.on ? Qt.darker(Theme.accent, 1.12) : Theme.surface300) : "transparent"

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height - Theme.space4 * 2
                color: root.on ? Theme.onAccent : Theme.line
                opacity: 0.3
            }

            UiText {
                anchors.centerIn: parent
                text: "›"
                font.pixelSize: 20
                color: root.on ? Theme.onAccent : Theme.ink
            }

            MouseArea {
                id: moreMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.available
                onClicked: root.moreClicked()
            }
        }
    }
}
