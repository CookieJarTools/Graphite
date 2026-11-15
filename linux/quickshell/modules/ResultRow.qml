// One search result, 44 px: its icon, its alias, the name (the match in the accent) and where
// it is, its launcher label, the keys that also do it, when it was last used, and its kind
// ("App", "File", "Folder", "Action") at the right end.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

Rectangle {
    id: root

    property var item
    property string match
    property bool selected: false
    signal hovered()
    signal activated(bool asAdmin)
    signal menuRequested(var event)

    readonly property string label: item && item.kind === "Apps" ? Search.labelOf(item.id) : ""
    readonly property string kindName: ({ Apps: "App", Files: "File", Folders: "Folder", Commands: "Action" })[item ? item.kind : ""] || ""

    implicitHeight: 44
    radius: Theme.radiusControl
    color: selected ? Theme.accentSoft : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

    Accessible.role: Accessible.ListItem
    Accessible.name: item ? item.name + (kindName ? ", " + kindName : "") : ""
    Accessible.selected: selected

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space3
        anchors.rightMargin: Theme.space3
        spacing: Theme.space3

        IconImage {
            implicitSize: 18
            source: !root.item ? ""
                : root.item.kind === "Apps" ? Quickshell.iconPath(root.item.icon, "application-x-executable")
                : root.item.kind === "Commands" ? Quickshell.iconPath(root.item.glyph, "system-run")
                : root.item.kind === "Folders" ? Quickshell.iconPath("folder", "inode-directory")
                : Quickshell.iconPath("text-x-generic", "unknown")
        }

        UiText {
            visible: ShellState.showHints || (root.match.length > 0 && !!root.item && !!root.item.alias)
            Layout.preferredWidth: 36
            textFormat: Text.StyledText
            text: root.item ? Search.mark(root.item.alias || "", root.match) : ""
            color: Theme.inkFaint
            font.family: Theme.fontMono
            font.pixelSize: Theme.sectionSize
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            UiText {
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: root.item ? Search.mark(root.item.name, root.match) : ""
                font.pixelSize: Theme.labelSize
                font.weight: Theme.labelWeight
            }

            UiText {
                Layout.fillWidth: true
                visible: !!(root.item && root.item.path)
                text: root.item && root.item.path ? root.item.path : ""
                color: Theme.inkFaint
                font.family: Theme.fontMono
                font.pixelSize: Theme.sectionSize
                elide: Text.ElideMiddle
            }
        }

        // The app's launcher label, in its colour.
        Rectangle {
            visible: root.label !== ""
            implicitWidth: labelRow.implicitWidth + Theme.space2 * 2
            implicitHeight: 20
            radius: 10
            color: "transparent"
            border.color: Theme.cardBorder
            border.width: 1

            RowLayout {
                id: labelRow
                anchors.centerIn: parent
                spacing: Theme.space1

                Rectangle {
                    implicitWidth: 6
                    implicitHeight: 6
                    radius: 3
                    color: Taskbar.labelColour(root.label)
                }

                UiText {
                    text: root.label
                    color: Theme.inkMuted
                    font.pixelSize: Theme.sectionSize
                }
            }
        }

        Repeater {
            model: ShellState.showHints && root.item && root.item.command ? root.item.command.keys : []
            KeyChip {
                required property var modelData
                text: modelData
            }
        }

        UiText {
            visible: text.length > 0
            text: root.item ? Search.timeAgo(root.item.time) : ""
            color: Theme.inkFaint
            font.pixelSize: Theme.sectionSize
        }

        UiText {
            Layout.minimumWidth: 40
            horizontalAlignment: Text.AlignRight
            text: root.kindName
            color: Theme.inkFaint
            font.pixelSize: Theme.hintSize
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onEntered: root.hovered()
        onClicked: event => {
            if (event.button === Qt.RightButton) root.menuRequested(event);
            else root.activated((event.modifiers & Qt.ControlModifier) !== 0);
        }
    }
}
