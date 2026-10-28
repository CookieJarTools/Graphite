// One search result: its kind, its alias, its icon, the name (the match in the accent) and
// where it is, its launcher label, the keys that also do it, and when it was last used.
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
    readonly property string kindGlyph: ({ Apps: "application-x-executable-symbolic", Files: "text-x-generic-symbolic", Folders: "folder-symbolic", Commands: "system-run-symbolic" })[item ? item.kind : "Apps"] || "application-x-executable-symbolic"

    implicitHeight: 44
    radius: Theme.radiusSm
    color: selected ? Theme.surface300 : "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.space2
        anchors.rightMargin: Theme.space3
        spacing: Theme.space3

        Glyph {
            name: root.kindGlyph
            opacity: 0.5
        }

        UiText {
            Layout.preferredWidth: 44
            textFormat: Text.StyledText
            opacity: ShellState.showHints || (root.match.length > 0 && !!root.item && !!root.item.alias) ? 1 : 0
            text: root.item ? Search.mark(root.item.alias || "", root.match) : ""
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }

        IconImage {
            implicitSize: 24
            source: !root.item ? ""
                : root.item.kind === "Apps" ? Quickshell.iconPath(root.item.icon, "application-x-executable")
                : root.item.kind === "Commands" ? Quickshell.iconPath(root.item.glyph, "system-run")
                : root.item.kind === "Folders" ? Quickshell.iconPath("folder", "inode-directory")
                : Quickshell.iconPath("text-x-generic", "unknown")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            UiText {
                Layout.fillWidth: true
                textFormat: Text.StyledText
                text: root.item ? Search.mark(root.item.name, root.match) : ""
                font.weight: Font.Medium
            }

            UiText {
                Layout.fillWidth: true
                visible: !!(root.item && root.item.path)
                text: root.item && root.item.path ? root.item.path : ""
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
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
            border.color: Theme.line
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
                    font.pixelSize: Theme.hintSize
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
            text: root.item ? Search.timeAgo(root.item.time) : ""
            color: Theme.inkMuted
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
