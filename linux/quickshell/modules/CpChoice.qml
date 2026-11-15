// A choice of several: a button showing the current one; a click drops the list below it
// (inside the page, so nothing floats off the window). options: [{ value, label }].
import QtQuick
import QtQuick.Layouts
import qs.config

ColumnLayout {
    id: root

    property var options: []
    property var value
    property bool open: false
    property int maxShown: 8
    signal picked(var value)

    readonly property var current: options.find(option => option.value === value)

    spacing: Theme.space1

    Rectangle {
        Layout.alignment: Qt.AlignRight
        implicitWidth: Math.max(160, shown.implicitWidth + Theme.space3 * 2 + 20)
        implicitHeight: 30
        radius: Theme.radiusControl
        color: buttonMouse.containsMouse || root.open ? Theme.hoverIcon : Theme.tileOff
        border.color: root.open ? Theme.accentText : Theme.cardBorder
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

        Accessible.role: Accessible.ComboBox
        Accessible.name: root.current ? root.current.label : "Choose"
        Accessible.onPressAction: root.open = !root.open

        UiText {
            id: shown
            anchors.left: parent.left
            anchors.leftMargin: Theme.space3
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.space3 * 2 - 16
            text: root.current ? root.current.label : "Choose"
        }

        Glyph {
            anchors.right: parent.right
            anchors.rightMargin: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            name: root.open ? "pan-up-symbolic" : "pan-down-symbolic"
            implicitSize: 14
            tint: Theme.inkFaint
        }

        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = !root.open
        }
    }

    Rectangle {
        Layout.alignment: Qt.AlignRight
        visible: root.open
        implicitWidth: Math.max(220, list.implicitWidth + Theme.space2 * 2)
        implicitHeight: Math.min(list.implicitHeight, root.maxShown * 30) + 5 * 2
        radius: Theme.radiusCard
        color: Theme.panel
        border.color: Theme.border
        border.width: 1

        Flickable {
            id: choices
            anchors.fill: parent
            anchors.margins: 5
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            WheelScroll { flickable: choices; step: 72 }

            ColumnLayout {
                id: list
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.open ? root.options : []

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitWidth: optionText.implicitWidth + Theme.space3 * 2 + 20
                        implicitHeight: 30
                        radius: Theme.radiusSm
                        color: optionMouse.containsMouse ? Theme.hoverIcon : "transparent"

                        UiText {
                            id: optionText
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space3
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.label
                            font.weight: parent.modelData.value === root.value ? Theme.labelWeight : Theme.bodyWeight
                            color: parent.modelData.value === root.value ? Theme.accentText : Theme.ink
                        }

                        MouseArea {
                            id: optionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            // The pick goes first: closing the list removes this option (and
                            // everything it could still say) at once.
                            onClicked: {
                                const value = parent.modelData.value;
                                root.picked(value);
                                Qt.callLater(() => { root.open = false; });
                            }
                        }
                    }
                }
            }
        }
    }
}
