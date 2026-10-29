// One row of a Control Panel page: a name, a line of explanation, and its control on the
// right (a switch, a button, a choice; whatever is put inside). With `opens`, the whole row
// is a button (clicked()); `below` holds anything that hangs under it (a list, a form). It
// leads with a symbolic `glyph`, or an app's `icon` in its own colours.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config

Rectangle {
    id: root

    property string label
    property string hint
    property string glyph
    property string icon
    property bool opens: false
    default property alias control: controls.data
    property alias below: belowArea.data
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + Theme.space3 * 2
    radius: Theme.radiusMd
    color: opens && mouse.containsMouse ? Theme.surface300 : Theme.surface200
    border.color: Theme.line
    border.width: 1
    opacity: enabled ? 1 : 0.5

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.opens
        enabled: root.opens
        cursorShape: root.opens ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    ColumnLayout {
        id: column
        x: Theme.space4
        y: Theme.space3
        width: parent.width - Theme.space4 * 2
        spacing: Theme.space3

        RowLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: 36
            spacing: Theme.space4

            Glyph {
                visible: root.glyph.length > 0 && root.icon.length === 0
                name: root.glyph
            }

            IconImage {
                visible: root.icon.length > 0
                implicitSize: 28
                source: root.icon ? Quickshell.iconPath(root.icon, "application-x-executable") : ""
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                UiText {
                    Layout.fillWidth: true
                    text: root.label
                    font.weight: Font.Medium
                }

                UiText {
                    Layout.fillWidth: true
                    visible: root.hint.length > 0
                    text: root.hint
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }

            RowLayout {
                id: controls
                spacing: Theme.space2
            }

            UiText {
                visible: root.opens
                text: "›"
                font.pixelSize: 20
                color: Theme.inkMuted
            }
        }

        ColumnLayout {
            id: belowArea
            Layout.fillWidth: true
            visible: children.length > 0
            spacing: Theme.space2
        }
    }
}
