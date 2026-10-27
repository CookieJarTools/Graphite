// The time and date on the bar, with a dot while a notification is unseen; opens the calendar.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

Rectangle {
    id: root

    property bool active: false
    signal clicked()

    implicitWidth: lines.implicitWidth + Theme.space3 * 2
    implicitHeight: 36
    radius: Theme.radiusSm
    color: mouse.containsMouse || active ? Theme.surface300 : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        id: lines
        anchors.centerIn: parent
        spacing: 0

        UiText {
            Layout.alignment: Qt.AlignRight
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: Theme.stripSize
            font.weight: Theme.stripWeight
        }

        UiText {
            Layout.alignment: Qt.AlignRight
            text: Qt.formatDateTime(clock.date, Qt.locale().dateFormat(Locale.ShortFormat))
            font.pixelSize: Theme.hintSize
            color: Theme.inkMuted
        }
    }

    Rectangle {
        visible: Notifs.unseen
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        width: 6
        height: 6
        radius: 3
        color: Theme.accent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
