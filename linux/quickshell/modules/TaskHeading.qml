// A column's heading in the task manager's list (TaskManager.qml): its total (mono) over its
// name (a small faint label), as on Windows; a click sorts by it.
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
    implicitHeight: 44
    radius: Theme.radiusRow
    color: headingMouse.containsMouse && key ? Theme.hoverRow : "transparent"

    Accessible.role: Accessible.ColumnHeader
    Accessible.name: label

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
            font.family: Theme.fontMono
            font.pixelSize: Theme.bodySize
            font.weight: Theme.labelWeight
        }

        UiText {
            Layout.fillWidth: true
            horizontalAlignment: heading.alignRight ? Text.AlignRight : Text.AlignLeft
            text: heading.label + (heading.sorting ? (manager.descending ? "  ↓" : "  ↑") : "")
            color: heading.sorting ? Theme.inkMuted : Theme.inkFaint
            font.pixelSize: Theme.sectionSize
            font.weight: Theme.labelWeight
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
