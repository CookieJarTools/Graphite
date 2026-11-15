// A bar history for the task manager's Processor tile: the last 40 samples (0 to 1) as bars
// 2 px apart in the accent, the newest on the right; older bars fade to 35%, and each bar's
// height eases to its new value.
import QtQuick
import qs.config

Item {
    id: root

    property var points: []
    property color colour: Theme.accent
    readonly property int count: 40
    readonly property real barWidth: Math.max(1, (width - 2 * (count - 1)) / count)
    readonly property int easing: Theme.durationBars

    implicitHeight: 44

    Repeater {
        model: root.count

        Rectangle {
            required property int index
            // Bars are filled from the right: the newest sample is the last bar.
            readonly property int sample: root.points.length - root.count + index
            readonly property real value: sample >= 0 ? Math.max(0, Math.min(1, root.points[sample] || 0)) : 0
            x: index * (root.barWidth + 2)
            width: root.barWidth
            height: Math.max(2, value * root.height)
            y: root.height - height
            radius: 1
            color: root.colour
            opacity: 0.35 + 0.65 * index / (root.count - 1)
            Behavior on height { NumberAnimation { duration: root.easing; easing.type: Easing.OutCubic } }
        }
    }
}
