// One pill on the bar (an item of Taskbar.items): an app with its icon, or a folder with a
// stack of its apps' icons; the label (the tag's name, a lone window's title, or the name);
// the number of windows or tabs; a dot while a window wants attention; the tag's colour; a
// mark under it while running; the icon pulsing while the app is starting. The bar handles the
// pointer for all its pills (Bar.qml).
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services

Rectangle {
    id: root

    required property var modelData
    required property int index
    readonly property var item: modelData
    readonly property bool isFolder: item.type === "folder"
    readonly property bool showLabel: ShellSettings.taskbar.showLabels !== false
    property bool hovered: false
    property bool lifted: false     // being dragged: its slot shows where it will land
    property bool mergeTarget: false
    property bool fresh: false      // new on the bar: grows in

    readonly property int count: isFolder ? 0 : item.windows.length > 1 ? item.windows.length
        : item.windows.length === 1 && item.windows[0].tabs > 1 ? item.windows[0].tabs : 0
    readonly property color tagColour: item.tag ? Taskbar.tagColour(item.tag.color) : "transparent"

    implicitWidth: content.implicitWidth + (showLabel ? Theme.space3 : Theme.space2) * 2
    implicitHeight: 36
    radius: Theme.radiusSm
    color: mergeTarget ? Theme.accentSoft : lifted ? Theme.surface100 : hovered || item.focused ? Theme.surface300 : "transparent"
    border.color: lifted ? Theme.lineStrong : "transparent"
    border.width: 1
    scale: mergeTarget ? 1.06 : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }
    Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

    // Started from the shell and no window yet: the icon pulses until one opens, for up to 30
    // seconds (Windows shows a busy pointer).
    property bool starting: false
    readonly property real startedAt: isFolder ? 0 : Apps.startedAt[item.key] || 0
    readonly property bool running: !!item.running
    function checkStarting() {
        const since = Date.now() - startedAt;
        starting = !isFolder && !running && since < 30000;
        if (starting) {
            stopStarting.interval = 30000 - since;
            stopStarting.restart();
        }
    }
    onStartedAtChanged: checkStarting()
    onRunningChanged: checkStarting()
    Timer {
        id: stopStarting
        onTriggered: root.starting = false
    }

    opacity: fresh ? 0 : 1
    Component.onCompleted: {
        if (fresh) appear.start();
        checkStarting();
    }
    NumberAnimation {
        id: appear
        target: root
        property: "opacity"
        from: 0
        to: 1
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.easeEnter
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space2
        opacity: root.lifted ? 0.35 : 1

        Item {
            implicitWidth: 24
            implicitHeight: 24

            SequentialAnimation on scale {
                running: root.starting
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.8; duration: 450; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 450; easing.type: Easing.InOutSine }
            }

            IconImage {
                visible: !root.isFolder
                anchors.fill: parent
                source: root.isFolder ? "" : Apps.iconFor(root.item.key, root.item.icon)
                opacity: root.item.running ? 1 : 0.6
            }

            // A folder: up to four of its apps, two by two.
            Grid {
                visible: root.isFolder
                anchors.fill: parent
                columns: 2
                spacing: 2

                Repeater {
                    model: root.isFolder ? root.item.apps.slice(0, 4) : []

                    IconImage {
                        required property var modelData
                        implicitSize: 11
                        source: Apps.iconFor(modelData.key, modelData.icon)
                        opacity: modelData.running ? 1 : 0.6
                    }
                }
            }

            // The tag's colour, on the icon's corner.
            Rectangle {
                visible: !!root.item.tag
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -2
                width: 9
                height: 9
                radius: 4.5
                color: root.tagColour
                border.color: Theme.surface200
                border.width: 1.5
            }

            Rectangle {
                visible: !!root.item.attention
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: -2
                width: 8
                height: 8
                radius: 4
                color: Theme.danger
                border.color: Theme.surface200
                border.width: 1.5
            }
        }

        UiText {
            visible: root.showLabel
            Layout.maximumWidth: 140
            text: Taskbar.labelOf(root.item)
            color: root.item.focused ? Theme.ink : Theme.inkMuted
            font.pixelSize: Theme.stripSize
            font.weight: Theme.stripWeight
        }

        UiText {
            visible: root.count > 1
            text: root.count
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }
    }

    Rectangle {
        visible: root.item.running && !root.lifted
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: root.item.focused ? 12 : 6
        height: 2
        radius: 1
        color: root.item.tag ? root.tagColour : root.item.focused ? Theme.ink : Theme.inkMuted
        Behavior on width { NumberAnimation { duration: Theme.durationFast } }
    }
}
