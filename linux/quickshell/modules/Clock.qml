// The time over the date on the bar ("Tue 10 Nov"), right aligned in even-width figures;
// opens the calendar. (The bell beside it carries the dot for an unseen notification.)
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
    implicitHeight: Theme.barButton
    radius: Theme.radiusCard
    color: active ? Theme.activeRow : mouse.containsMouse ? Theme.hoverIcon : "transparent"
    scale: mouse.pressed ? Theme.grow(0.94) : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.Button
    Accessible.name: Qt.formatDateTime(clock.date, "HH:mm, dddd d MMMM")

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
            font.weight: Theme.headingWeight
            font.features: { "tnum": 1 }
        }

        UiText {
            Layout.alignment: Qt.AlignRight
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            font.pixelSize: Theme.sectionSize
            font.features: { "tnum": 1 }
            color: Theme.inkMuted
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
