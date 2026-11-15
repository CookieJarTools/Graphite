// One button on the bar (an item of Taskbar.items): an app with its icon, or a folder with a
// stack of its apps' icons; the label (the tag's name, a lone window's title, or the name);
// the number of windows or tabs; a dot while a window wants attention; the tag's colour; the
// running mark under it (a dot while running, a bar in the accent while in front); the icon
// pulsing while the app is starting. It lifts under the pointer and presses in. The bar
// handles the pointer for all its buttons (Bar.qml).
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
    property bool pressed: false
    property bool lifted: false     // being dragged: its slot shows where it will land
    property bool mergeTarget: false
    property bool fresh: false      // new on the bar: grows in

    readonly property int count: isFolder ? 0 : item.windows.length > 1 ? item.windows.length
        : item.windows.length === 1 && item.windows[0].tabs > 1 ? item.windows[0].tabs : 0
    readonly property color tagColour: item.tag ? Taskbar.tagColour(item.tag.color) : "transparent"

    implicitWidth: Math.max(Theme.barButton, content.implicitWidth + Theme.space3 * 2)
    implicitHeight: Theme.barButton
    radius: Theme.radiusCard
    color: mergeTarget ? Theme.accentSoft : lifted ? Theme.window : hovered ? Theme.hoverIcon : "transparent"
    border.color: lifted ? Theme.lineStrong : mergeTarget ? Theme.accent : "transparent"
    border.width: 1
    scale: mergeTarget ? Theme.grow(1.06) : pressed ? Theme.grow(0.94) : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    // Up 3 px under the pointer.
    transform: Translate {
        y: root.hovered && !root.lifted ? -Theme.move(3) : 0
        Behavior on y { NumberAnimation { duration: Theme.durationLift; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSpring } }
    }

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
        duration: Theme.durationBase
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.easeOut
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space2
        opacity: root.lifted ? 0.35 : 1

        Item {
            implicitWidth: 20
            implicitHeight: 20

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
                        implicitSize: 9
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
                border.color: Theme.panel
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
                border.color: Theme.panel
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
            Behavior on color { ColorAnimation { duration: Theme.durationInstant } }
        }

        UiText {
            visible: root.count > 1
            text: root.count
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }
    }

    // Running: none while closed, a dot while running, a bar in the accent (or the tag's
    // colour) while in front.
    Rectangle {
        visible: width > 0 && !root.lifted
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        width: !root.item.running ? 0 : root.item.focused ? 16 : 4
        height: 3
        radius: 1.5
        color: root.item.tag ? root.tagColour : root.item.focused ? Theme.accent : Theme.runningDot
        Behavior on width { NumberAnimation { duration: Theme.durationIndicator; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeSpring } }
        Behavior on color { ColorAnimation { duration: Theme.durationIndicator } }
    }
}
