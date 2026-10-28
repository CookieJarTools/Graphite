// The task manager (Ctrl+Shift+Esc, as on Windows). Processes: the apps with windows and the
// background processes, with how much processor and memory each uses; pick one and End task
// (a double click on an app switches to it). Performance: the processor, memory, disk and
// network, each with a minute's graph. Numbers come from Tasks.qml while it is open.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.config
import qs.services

FloatingWindow {
    id: root

    visible: ShellState.taskManagerOpen
    title: "Task Manager"
    implicitWidth: 820
    implicitHeight: 640
    minimumSize: Qt.size(560, 420)
    color: Theme.surface100

    property string tab: "processes"
    property string selected: ""   // the chosen task's key
    property string sortBy: "cpu"  // "name", "cpu" or "memory"

    onVisibleChanged: {
        if (!visible) ShellState.taskManagerOpen = false;
        else keys.forceActiveFocus();
    }

    Binding {
        target: Tasks
        property: "watching"
        value: root.visible
    }

    function sorted(list) {
        return list.slice().sort((first, second) => sortBy === "name" ? first.name.localeCompare(second.name)
            : sortBy === "memory" ? second.memory - first.memory : second.cpu - first.cpu);
    }

    readonly property var everything: Tasks.apps.concat(Tasks.background)
    readonly property var chosen: everything.find(task => task.key === selected) || null

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.taskManagerOpen = false
        Keys.onDeletePressed: if (root.chosen) Tasks.end(root.chosen)

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- head: the tabs, End task, close ----------

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                color: Theme.header

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space6
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space2

                    UiText {
                        text: "Task Manager"
                        font.pixelSize: 20
                        font.weight: Font.DemiBold
                    }

                    Item { implicitWidth: Theme.space4 }

                    Repeater {
                        model: [{ id: "processes", name: "Processes" }, { id: "performance", name: "Performance" }]

                        Rectangle {
                            required property var modelData
                            readonly property bool on: root.tab === modelData.id
                            implicitWidth: tabText.implicitWidth + Theme.space4 * 2
                            implicitHeight: 32
                            radius: 16
                            color: on ? Theme.accentSoft : tabMouse.containsMouse ? Theme.surface300 : "transparent"
                            border.color: on ? Theme.accent : Theme.line
                            border.width: 1

                            UiText {
                                id: tabText
                                anchors.centerIn: parent
                                text: parent.modelData.name
                                color: parent.on ? Theme.ink : Theme.inkMuted
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: tabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.tab = parent.modelData.id
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    PillButton {
                        visible: root.tab === "processes"
                        danger: true
                        text: "End task"
                        enabled: root.chosen !== null && Tasks.canEnd(root.chosen)
                        onClicked: {
                            Tasks.end(root.chosen);
                            root.selected = "";
                        }
                    }

                    BarButton {
                        glyph: "window-close-symbolic"
                        onClicked: ShellState.taskManagerOpen = false
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.line
                }
            }

            // ---------- processes ----------

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Layout.leftMargin: Theme.space6
                Layout.rightMargin: Theme.space6
                visible: root.tab === "processes"
                spacing: 0

                Heading { Layout.fillWidth: true; text: "Name"; key: "name"; alignRight: false }
                Heading { Layout.preferredWidth: 110; text: "CPU " + Math.round(Tasks.cpu * 100) + "%"; key: "cpu" }
                Heading { Layout.preferredWidth: 130; text: "Memory " + Math.round(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal) * 100) + "%"; key: "memory" }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.tab === "processes"
                clip: true
                contentHeight: processList.implicitHeight + Theme.space4
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: processList
                    x: Theme.space4
                    width: parent.width - Theme.space4 * 2
                    spacing: 0

                    Group { text: "Apps (" + Tasks.apps.length + ")" }
                    Repeater {
                        model: root.sorted(Tasks.apps)
                        TaskRow {}
                    }

                    Group { text: "Background processes (" + Tasks.background.length + ")" }
                    Repeater {
                        model: root.sorted(Tasks.background)
                        TaskRow {}
                    }
                }
            }

            // ---------- performance ----------

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Theme.space6
                visible: root.tab === "performance"
                columns: 2
                columnSpacing: Theme.space3
                rowSpacing: Theme.space3

                Meter {
                    title: "Processor"
                    value: Math.round(Tasks.cpu * 100) + "%"
                    detail: Machine.about.cpu || ""
                    points: Tasks.history.cpu
                }
                Meter {
                    title: "Memory"
                    value: Tasks.size(Tasks.memoryUsed) + " of " + Tasks.size(Tasks.memoryTotal)
                    detail: Math.round(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal) * 100) + "% in use"
                    points: Tasks.history.memory
                }
                Meter {
                    title: "Disk"
                    value: "Read " + Tasks.speed(Tasks.diskRead) + " · Write " + Tasks.speed(Tasks.diskWrite)
                    detail: "Graph up to 100 MB/s"
                    points: Tasks.history.disk
                }
                Meter {
                    title: "Network"
                    value: "Down " + Tasks.speed(Tasks.netDown) + " · Up " + Tasks.speed(Tasks.netUp)
                    detail: "Graph up to 100 Mbit/s"
                    points: Tasks.history.net
                }
            }
        }
    }

    // ---------- pieces ----------

    component Heading: Rectangle {
        id: heading
        property string text
        property string key
        property bool alignRight: true
        implicitHeight: 32
        color: headingMouse.containsMouse ? Theme.surface200 : "transparent"
        radius: Theme.radiusSm

        UiText {
            anchors.fill: parent
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: Theme.space2
            horizontalAlignment: heading.alignRight ? Text.AlignRight : Text.AlignLeft
            text: heading.text + (root.sortBy === heading.key ? "  ↓" : "")
            color: root.sortBy === heading.key ? Theme.ink : Theme.inkMuted
            font.pixelSize: Theme.hintSize
            font.weight: Font.DemiBold
        }

        MouseArea {
            id: headingMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.sortBy = heading.key
        }
    }

    component Group: UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space3
        Layout.bottomMargin: Theme.space1
        Layout.leftMargin: Theme.space2
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    component TaskRow: Rectangle {
        id: row
        required property var modelData
        readonly property bool on: root.selected === modelData.key
        Layout.fillWidth: true
        implicitHeight: 36
        radius: Theme.radiusSm
        color: on ? Theme.accentSoft : rowMouse.containsMouse ? Theme.surface200 : "transparent"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: Theme.space2
            spacing: 0

            IconImage {
                visible: row.modelData.app
                implicitSize: 18
                Layout.rightMargin: Theme.space3
                source: Quickshell.iconPath(String(row.modelData.icon).toLowerCase(), "application-x-executable")
            }

            UiText {
                Layout.fillWidth: true
                text: row.modelData.name + (row.modelData.app && row.modelData.pids.length > 1 ? "  (" + row.modelData.pids.length + ")" : "")
            }

            UiText {
                Layout.preferredWidth: 110
                horizontalAlignment: Text.AlignRight
                text: row.modelData.cpu.toFixed(1) + "%"
                font.family: Theme.fontMono
                font.pixelSize: Theme.identifierSize
                color: row.modelData.cpu > 50 ? Theme.danger : Theme.ink
            }

            UiText {
                Layout.preferredWidth: 130
                horizontalAlignment: Text.AlignRight
                text: Tasks.size(row.modelData.memory)
                font.family: Theme.fontMono
                font.pixelSize: Theme.identifierSize
            }
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.selected = row.modelData.key
            onDoubleClicked: {
                if (row.modelData.windows.length) {
                    Hyprland.dispatch(`hl.dsp.focus({ window = "address:${row.modelData.windows[0]}" })`);
                    ShellState.taskManagerOpen = false;
                }
            }
        }
    }

    component Meter: Rectangle {
        id: meter
        property string title
        property string value
        property string detail
        property var points: []
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Theme.radiusMd
        color: Theme.surface200
        border.color: Theme.line
        border.width: 1
        onPointsChanged: graph.requestPaint()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space1

            UiText {
                text: meter.title
                font.weight: Font.DemiBold
            }

            UiText {
                Layout.fillWidth: true
                text: meter.value
                font.pixelSize: 18
            }

            UiText {
                Layout.fillWidth: true
                text: meter.detail
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            Canvas {
                id: graph
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: Theme.space2
                onPaint: {
                    const context = getContext("2d");
                    context.reset();
                    const points = meter.points;
                    context.strokeStyle = Theme.line;
                    context.lineWidth = 1;
                    context.strokeRect(0.5, 0.5, width - 1, height - 1);
                    if (points.length < 2) return;
                    const step = width / 29;
                    const x = index => width - (points.length - 1 - index) * step;
                    const y = value => height - 1 - value * (height - 2);
                    context.beginPath();
                    context.moveTo(x(0), height);
                    points.forEach((value, index) => context.lineTo(x(index), y(value)));
                    context.lineTo(x(points.length - 1), height);
                    context.closePath();
                    context.fillStyle = Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18);
                    context.fill();
                    context.beginPath();
                    points.forEach((value, index) => index ? context.lineTo(x(index), y(value)) : context.moveTo(x(index), y(value)));
                    context.strokeStyle = Theme.accent;
                    context.lineWidth = 2;
                    context.stroke();
                }
            }
        }
    }
}
