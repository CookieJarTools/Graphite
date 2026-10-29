// A column's heading in the task manager's list (TaskManager.qml): its total over its name,
// as on Windows; a click sorts by it.
import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: heading
    required property var manager
    property string label
    property string figure
    property string key
    property bool alignRight: true
    readonly property bool sorting: key.length > 0 && manager.sortBy === key
    implicitHeight: 52
    radius: Theme.radiusSm
    color: headingMouse.containsMouse && key ? Theme.surface200 : "transparent"

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space2
        anchors.rightMargin: Theme.space3
        anchors.topMargin: Theme.space1
        anchors.bottomMargin: Theme.space1
        spacing: 0

        Item { Layout.fillHeight: true }

        UiText {
            Layout.fillWidth: true
            visible: heading.figure.length > 0
            horizontalAlignment: heading.alignRight ? Text.AlignRight : Text.AlignLeft
            text: heading.figure
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        UiText {
            Layout.fillWidth: true
            horizontalAlignment: heading.alignRight ? Text.AlignRight : Text.AlignLeft
            text: heading.label + (heading.sorting ? (manager.descending ? "  ↓" : "  ↑") : "")
            color: heading.sorting ? Theme.ink : Theme.inkMuted
            font.pixelSize: Theme.hintSize
            font.weight: heading.sorting ? Font.DemiBold : Font.Normal
        }
    }

    MouseArea {
        id: headingMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: heading.key.length > 0
        onClicked: manager.sortOn(heading.key)
    }
}
