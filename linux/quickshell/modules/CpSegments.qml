// A segmented choice: a track 2 px in, its options side by side as 28 px segments, the chosen
// one lit. options: [{ value, label }].
import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root

    property var options: []
    property var value
    signal picked(var value)

    implicitWidth: segments.implicitWidth + 4
    implicitHeight: 32
    radius: Theme.radiusControl
    color: Theme.tileOff
    border.color: Theme.cardBorder
    border.width: 1

    Accessible.role: Accessible.PageTabList

    Row {
        id: segments
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.options

            Rectangle {
                id: segment
                required property var modelData
                readonly property bool on: modelData.value === root.value
                width: Math.max(56, label.implicitWidth + Theme.space3 * 2)
                height: 28
                radius: Theme.radiusSm
                color: on ? Theme.segmentOn : mouse.containsMouse ? Theme.hoverRow : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

                Accessible.role: Accessible.PageTab
                Accessible.name: modelData.label
                Accessible.selected: on
                Accessible.onPressAction: root.picked(modelData.value)

                UiText {
                    id: label
                    anchors.centerIn: parent
                    text: segment.modelData.label
                    color: segment.on ? Theme.ink : Theme.inkMuted
                    font.weight: Theme.labelWeight
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(segment.modelData.value)
                }
            }
        }
    }
}
