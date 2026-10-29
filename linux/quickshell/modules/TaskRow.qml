// A row of the task manager's list (TaskManager.qml, `manager`): a group's heading, an entry
// (an app, a background process, a part of the desktop) or a process beneath one; its figures
// on their shades, a chevron to open it, a right-click menu.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

Rectangle {
    id: row
    required property var manager
    required property var modelData
    readonly property bool heading: !!modelData.group
    readonly property var task: modelData.task || ({ key: "", name: "", processes: [], windows: [], cpu: 0, memory: 0, disk: 0 })
    readonly property int depth: modelData.depth || 0
    readonly property bool expandable: !!modelData.expandable
    readonly property bool open: !!modelData.open
    readonly property bool on: !heading && manager.selected === task.key
    readonly property int count: task.processes ? task.processes.length : 0
    Layout.fillWidth: true
    implicitHeight: heading ? 40 : 34
    radius: Theme.radiusSm
    color: on ? Theme.accentSoft : rowMouse.containsMouse && !heading ? Theme.surface200 : "transparent"

    UiText {
        visible: row.heading
        anchors.left: parent.left
        anchors.leftMargin: manager.lead
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space1
        text: row.modelData.group || ""
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        enabled: !row.heading
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) manager.openMenu(manager.taskFor(row.task.key) || row.task, row, event.x, event.y);
            else manager.selected = row.task.key;
        }
        onDoubleClicked: event => {
            if (event.button !== Qt.LeftButton) return;
            if (row.task.windows && row.task.windows.length) manager.switchTo(row.task);
            else if (row.expandable) manager.toggle(row.task.key);
        }
    }

    // The chosen row's mark.
    Rectangle {
        visible: row.on
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        height: 16
        radius: 2
        color: Theme.accent
    }

    RowLayout {
        visible: !row.heading
        anchors.fill: parent
        spacing: 0

        // The chevron, and a process's step in.
        Item {
            implicitWidth: manager.lead + row.depth * 26
            Layout.fillHeight: true

            Glyph {
                visible: row.expandable
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                name: row.open ? "pan-down-symbolic" : "pan-end-symbolic"
                tint: Theme.inkMuted
            }

            MouseArea {
                anchors.fill: parent
                enabled: row.expandable
                onClicked: manager.toggle(row.task.key)
            }
        }

        Item {
            implicitWidth: 18
            implicitHeight: 18
            Layout.rightMargin: Theme.space3

            IconImage {
                visible: row.depth === 0 && !!(row.task.app || row.task.desk)
                anchors.fill: parent
                source: Quickshell.iconPath(String(row.task.icon || "").toLowerCase(), "application-x-executable")
            }

            Glyph {
                visible: row.depth === 1 || !(row.task.app || row.task.desk)
                anchors.centerIn: parent
                name: "application-x-executable-symbolic"
                tint: Theme.inkMuted
                opacity: 0.7
            }
        }

        UiText {
            Layout.fillWidth: true
            text: row.task.name
            font.weight: row.depth === 0 && !!(row.task.app || row.task.desk) ? Font.Medium : Font.Normal
        }

        UiText {
            visible: row.depth === 0 && row.count > 1
            Layout.rightMargin: Theme.space3
            text: "(" + row.count + ")"
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
        }

        UiText {
            visible: row.depth === 1
            Layout.rightMargin: Theme.space3
            text: "PID " + row.task.pid
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }

        Repeater {
            model: row.heading ? [] : manager.cells(row.task)

            Rectangle {
                required property var modelData
                Layout.preferredWidth: modelData.width
                Layout.fillHeight: true
                color: modelData.shade

                UiText {
                    anchors.fill: parent
                    anchors.rightMargin: Theme.space3
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    text: parent.modelData.text
                    color: parent.modelData.muted ? Theme.inkMuted : Theme.ink
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }
            }
        }
    }
}
