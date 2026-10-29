// A choice of several: a button showing the current one; a click drops the list below it
// (inside the page, so nothing floats off the window). options: [{ value, label }].
import QtQuick
import QtQuick.Layouts
import qs.config

ColumnLayout {
    id: root

    property var options: []
    property var value
    property bool open: false
    property int maxShown: 8
    signal picked(var value)

    readonly property var current: options.find(option => option.value === value)

    spacing: Theme.space1

    Rectangle {
        Layout.alignment: Qt.AlignRight
        implicitWidth: Math.max(160, shown.implicitWidth + Theme.space3 * 2 + 20)
        implicitHeight: 32
        radius: Theme.radiusSm
        color: buttonMouse.containsMouse || root.open ? Theme.surface300 : Theme.surface100
        border.color: root.open ? Theme.accent : Theme.line
        border.width: 1

        UiText {
            id: shown
            anchors.left: parent.left
            anchors.leftMargin: Theme.space3
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.space3 * 2 - 16
            text: root.current ? root.current.label : "Choose"
        }

        UiText {
            anchors.right: parent.right
            anchors.rightMargin: Theme.space3
            anchors.verticalCenter: parent.verticalCenter
            text: root.open ? "⌃" : "⌄"
            color: Theme.inkMuted
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    Rectangle {
        Layout.alignment: Qt.AlignRight
        visible: root.open
        implicitWidth: Math.max(220, list.implicitWidth + Theme.space2 * 2)
        implicitHeight: Math.min(list.implicitHeight, root.maxShown * 32) + Theme.space1 * 2
        radius: Theme.radiusSm
        color: Theme.surface100
        border.color: Theme.line
        border.width: 1

        Flickable {
            anchors.fill: parent
            anchors.margins: Theme.space1
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: list
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.open ? root.options : []

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: optionText.implicitWidth + Theme.space3 * 2 + 20
                        implicitHeight: 32
                        radius: Theme.radiusSm
                        color: optionMouse.containsMouse ? Theme.surface300 : "transparent"

                        UiText {
                            id: optionText
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.label
                            font.weight: parent.modelData.value === root.value ? Font.DemiBold : Font.Normal
                            color: parent.modelData.value === root.value ? Theme.accent : Theme.ink
                        }

                        MouseArea {
                            id: optionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            // The pick goes first: closing the list removes this option (and
                            // everything it could still say) at once.
                            onClicked: {
                                const value = parent.modelData.value;
                                root.picked(value);
                                Qt.callLater(() => { root.open = false; });
                            }
                        }
                    }
                }
            }
        }
    }
}
