// An app on the bar: its icon and name, a mark under it while it has windows (longer for the
// focused one), the number of windows when there are several. A click starts it or brings its
// windows forward in turn; a middle click opens another; a right click opens its menu.
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.config
import qs.services

Rectangle {
    id: root

    required property var modelData
    property string screenName
    readonly property var group: modelData
    readonly property bool running: group.windows.length > 0
    readonly property bool focused: group.windows.some(window => window.activated)

    implicitWidth: content.implicitWidth + Theme.space3 * 2
    implicitHeight: 36
    radius: Theme.radiusSm
    color: mouse.containsMouse || focused ? Theme.surface300 : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space2

        IconImage {
            implicitSize: 24
            source: Apps.iconOf(root.group)
            opacity: root.running ? 1 : 0.6
        }

        UiText {
            Layout.maximumWidth: 140
            text: Apps.nameOf(root.group)
            color: root.focused ? Theme.ink : Theme.inkMuted
            font.pixelSize: Theme.stripSize
            font.weight: Theme.stripWeight
        }

        UiText {
            visible: root.group.windows.length > 1
            text: root.group.windows.length
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }
    }

    Rectangle {
        visible: root.running
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: root.focused ? 12 : 6
        height: 2
        radius: 1
        color: root.focused ? Theme.ink : Theme.inkMuted
        Behavior on width { NumberAnimation { duration: Theme.durationFast } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                ShellState.openAppMenu(root.group, root.screenName, root.mapToItem(null, root.width / 2, 0).x);
            } else if (event.button === Qt.MiddleButton) {
                Apps.launch(root.group.entry);
            } else {
                ShellState.closePanels();
                Apps.activate(root.group);
            }
        }
    }
}
