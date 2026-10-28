// "New tag" for a window: a name and one of the tag colours (the first free one to start),
// over the bar. Create (or Enter) tags the window with it; Cancel, Escape or a click
// elsewhere leaves it be.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property string screenName
    property var barWindow: null

    readonly property var state: ShellState.tagPanel
    readonly property bool open: state !== null && state.screen === screenName
    property string colour: "blue"

    visible: open
    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: Theme.taskbarHeight + Theme.space2 * 2
        left: state ? Math.max(Theme.space2, Math.min(state.x, screen.width - implicitWidth - Theme.space2)) : 0
    }
    exclusiveZone: 0
    implicitWidth: 320
    implicitHeight: column.implicitHeight + Theme.space4 * 2
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "graphite-panel"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: if (open) {
        colour = Taskbar.freeColour();
        nameInput.text = "";
        nameInput.forceActiveFocus();
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: ShellState.tagPanel = null
    }

    function create() {
        Taskbar.createTag(state.hwnd, nameInput.text, colour);
        ShellState.tagPanel = null;
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Theme.space4
            spacing: Theme.space3

            ColumnLayout {
                spacing: 0

                UiText {
                    text: "New tag"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                UiText {
                    Layout.fillWidth: true
                    text: root.state ? (root.state.title || "Untitled window") : ""
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: Theme.radiusSm
                color: Theme.surface100
                border.color: nameInput.activeFocus ? Theme.accent : Theme.line
                border.width: 1

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    verticalAlignment: TextInput.AlignVCenter
                    maximumLength: 24
                    color: Theme.ink
                    selectionColor: Theme.accentSoft
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.bodySize
                    Keys.onReturnPressed: root.create()
                    Keys.onEnterPressed: root.create()
                    Keys.onEscapePressed: ShellState.tagPanel = null

                    UiText {
                        anchors.fill: parent
                        visible: nameInput.text.length === 0
                        text: "Work, Play, Dev..."
                        color: Theme.inkMuted
                    }
                }
            }

            RowLayout {
                spacing: Theme.space2

                Repeater {
                    model: Taskbar.tagColours

                    Rectangle {
                        required property var modelData
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: "transparent"
                        border.color: root.colour === modelData ? Theme.ink : "transparent"
                        border.width: 2

                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: Taskbar.tagColour(parent.modelData)
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.colour = parent.modelData
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                Item { Layout.fillWidth: true }

                MenuRow {
                    text: "Cancel"
                    onClicked: ShellState.tagPanel = null
                }

                Rectangle {
                    implicitWidth: createLabel.implicitWidth + Theme.space4 * 2
                    implicitHeight: 32
                    radius: Theme.radiusSm
                    color: createMouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent

                    UiText {
                        id: createLabel
                        anchors.centerIn: parent
                        text: "Create"
                        color: Theme.onAccent
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: createMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.create()
                    }
                }
            }
        }
    }
}
