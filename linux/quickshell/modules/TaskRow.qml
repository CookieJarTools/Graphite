// A row of the task manager's list (TaskManager.qml, `manager`), 32 px: a group's heading, an
// entry (an app, a background process, a part of the desktop) or a process beneath one; its
// PID and figures in mono, right aligned, on their shades; a chevron to open it, a right-click
// menu. The chosen row is tinted with the accent.
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
    implicitHeight: heading ? 36 : 32
    radius: Theme.radiusRow
    color: on ? Theme.accentSoft : rowMouse.containsMouse && !heading ? Theme.hoverRow : "transparent"
    clip: true

    Accessible.role: heading ? Accessible.StaticText : Accessible.Row
    Accessible.name: heading ? (modelData.group || "") : task.name
    Accessible.selected: on

    UiText {
        visible: row.heading
        anchors.left: parent.left
        anchors.leftMargin: manager.lead
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.space1 + 2
        text: row.modelData.group || ""
        color: Theme.inkFaint
        font.pixelSize: Theme.sectionSize
        font.weight: Theme.labelWeight
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
                implicitSize: 14
                tint: Theme.inkFaint
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
                implicitSize: 14
                tint: Theme.inkFaint
            }
        }

        UiText {
            Layout.fillWidth: true
            text: row.task.name
            color: row.depth === 1 ? Theme.inkMuted : Theme.ink
            font.weight: row.depth === 0 && !!(row.task.app || row.task.desk) ? Theme.labelWeight : Theme.bodyWeight
        }

        UiText {
            visible: row.depth === 0 && row.count > 1
            Layout.rightMargin: Theme.space3
            text: row.count
            color: Theme.inkFaint
            font.family: Theme.fontMono
            font.pixelSize: Theme.sectionSize
        }

        // The PID: a process's own, or an entry's when it is a single process.
        UiText {
            Layout.preferredWidth: manager.pidWidth
            Layout.fillHeight: true
            rightPadding: Theme.space3
            horizontalAlignment: Text.AlignRight
            text: row.depth === 1 ? String(row.task.pid || "") : row.task.pids && row.task.pids.length === 1 ? String(row.task.pids[0]) : ""
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
                    color: parent.modelData.muted ? Theme.inkFaint : Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }
            }
        }
    }
}
