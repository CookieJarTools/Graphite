// A quick-settings tile: a glyph over its name and a line of detail; filled with the accent
// while on. A click on it switches it; with `more`, the arrow in its corner opens its list
// instead (networks, devices), as on Windows.
import QtQuick
import QtQuick.Layouts
import qs.config

Rectangle {
    id: root

    property string glyph
    property string label
    property string detail
    property bool on: false
    property bool available: true
    property bool more: false
    signal toggled()
    signal moreClicked()

    readonly property color inkOn: Theme.onAccent

    implicitHeight: content.implicitHeight + Theme.space3 * 2
    radius: Theme.radiusCard
    color: on ? (mouse.containsMouse ? Qt.lighter(Theme.accentFill, 1.08) : Theme.accentFill) : (mouse.containsMouse ? Theme.hoverIcon : Theme.tileOff)
    opacity: available ? 1 : 0.5
    scale: mouse.pressed ? Theme.grow(0.97) : 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }
    Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checkable: true
    Accessible.checked: on
    Accessible.onToggleAction: root.toggled()

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        onClicked: root.toggled()
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.space3
        spacing: 0

        Glyph {
            Layout.bottomMargin: Theme.space2
            name: root.glyph
            implicitSize: 18
            tint: root.on ? root.inkOn : Theme.ink
        }

        UiText {
            Layout.fillWidth: true
            text: root.label
            font.weight: Theme.labelWeight
            color: root.on ? root.inkOn : Theme.ink
        }

        UiText {
            Layout.fillWidth: true
            text: root.detail
            font.pixelSize: Theme.hintSize
            color: root.on ? root.inkOn : Theme.inkMuted
            opacity: root.on ? 0.8 : 1
        }
    }

    // The way into the tile's list.
    Rectangle {
        visible: root.more
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.space2
        width: 28
        height: 28
        radius: Theme.radiusRow
        color: moreMouse.containsMouse ? (root.on ? Theme.tint("#ffffff", 0.16) : Theme.hoverIcon) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

        Accessible.role: Accessible.Button
        Accessible.name: root.label + " list"
        Accessible.onPressAction: root.moreClicked()

        Glyph {
            anchors.centerIn: parent
            name: "go-next-symbolic"
            implicitSize: 14
            tint: root.on ? root.inkOn : Theme.inkMuted
        }

        MouseArea {
            id: moreMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.available
            onClicked: root.moreClicked()
        }
    }
}
