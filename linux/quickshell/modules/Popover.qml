// Over a pill: its windows (an app with several), or a folder's apps with their windows. A
// row brings its window forward or starts its app; a right click gives the window's (or the
// app's) menu. A folder's head has its name, renamed in place (Enter saves, Escape keeps the
// old name), and a pin. A click elsewhere closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.services

PanelWindow {
    id: root

    required property string screenName
    property var barWindow: null
    property var bar: null

    readonly property var state: ShellState.popover
    readonly property var item: state && state.screen === screenName ? Taskbar.items.find(candidate => candidate.ref === state.ref) || null : null
    readonly property bool open: item !== null
    readonly property bool isFolder: open && item.type === "folder"
    readonly property bool renaming: isFolder && ShellState.renaming === item.id

    visible: open
    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: Theme.taskbarHeight + Theme.space2 * 2
        left: state ? Math.max(Theme.space2, Math.min(state.x - implicitWidth / 2, screen.width - implicitWidth - Theme.space2)) : 0
    }
    exclusiveZone: 0
    implicitWidth: 320
    implicitHeight: card.implicitHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "graphite-panel"
    WlrLayershell.keyboardFocus: renaming ? WlrKeyboardFocus.Exclusive : open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // The folder it showed went (ungrouped, merged): nothing left to show. A folder just made
    // is not on the bar for a moment yet; that is no reason to close.
    property bool shownOnce: false
    onStateChanged: shownOnce = false
    onItemChanged: {
        if (item) shownOnce = true;
        else if (shownOnce && state && state.screen === screenName) ShellState.popover = null;
    }

    HyprlandFocusGrab {
        windows: root.barWindow ? [root, root.barWindow] : [root]
        active: root.open && ShellState.menu === null
        onCleared: {
            root.finishRename(true);
            ShellState.popover = null;
        }
    }

    function finishRename(keep) {
        if (!renaming) return;
        if (keep && nameInput.text.trim()) Taskbar.renameFolder(item.id, nameInput.text);
        ShellState.renaming = "";
    }

    onRenamingChanged: if (renaming) {
        nameInput.text = item.name;
        nameInput.selectAll();
        nameInput.forceActiveFocus();
    }

    function at(row, x) {
        const point = row.mapToItem(null, x, 0);
        return { screen: screenName, x: margins.left + point.x, y: screen.height - margins.bottom - implicitHeight + point.y, above: false };
    }

    // An app's rows inside a folder, or a lone app's own windows.
    readonly property var rows: {
        if (!open) return [];
        const list = [];
        const apps = isFolder ? item.apps : [item];
        for (const app of apps) {
            if (isFolder) list.push({ kind: "app", app: app });
            if (!isFolder || app.windows.length > 1) {
                for (const window of app.windows) list.push({ kind: "window", app: app, window: window, indented: isFolder });
            }
        }
        return list;
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: column.implicitHeight + Theme.space2 * 2
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Theme.space2
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space2
                Layout.preferredHeight: 32
                spacing: Theme.space2

                UiText {
                    Layout.fillWidth: true
                    visible: !root.renaming
                    text: root.open ? (root.isFolder ? root.item.name : root.item.name) : ""
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.renaming
                    implicitHeight: 28
                    radius: Theme.radiusSm
                    color: Theme.surface100
                    border.color: Theme.accent
                    border.width: 1

                    TextInput {
                        id: nameInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        verticalAlignment: TextInput.AlignVCenter
                        maximumLength: 40
                        color: Theme.ink
                        selectionColor: Theme.accentSoft
                        font.family: Theme.fontSans
                        font.pixelSize: Theme.bodySize
                        Keys.onReturnPressed: root.finishRename(true)
                        Keys.onEnterPressed: root.finishRename(true)
                        Keys.onEscapePressed: root.finishRename(false)
                    }
                }

                Rectangle {
                    visible: root.isFolder && !!root.item.label
                    implicitWidth: categoryText.implicitWidth + Theme.space2 * 2
                    implicitHeight: 20
                    radius: 10
                    color: Theme.surface300

                    UiText {
                        id: categoryText
                        anchors.centerIn: parent
                        text: "category"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }

                BarButton {
                    visible: root.isFolder && !root.renaming
                    implicitWidth: 28
                    implicitHeight: 28
                    glyph: root.isFolder && root.item.pinned ? "view-pin-symbolic" : "pin-symbolic"
                    active: root.isFolder && root.item.pinned
                    onClicked: Taskbar.setFolderPinned(root.item.id, !root.item.pinned)
                }
            }

            UiText {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space2
                visible: root.renaming
                text: "Enter  Save    Esc  Cancel"
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            UiText {
                Layout.fillWidth: true
                Layout.margins: Theme.space2
                visible: root.isFolder && root.rows.length === 0
                text: "No apps with this label"
                color: Theme.inkMuted
            }

            Repeater {
                model: root.rows

                Rectangle {
                    id: line

                    required property var modelData
                    readonly property bool isWindow: modelData.kind === "window"
                    readonly property var window: modelData.window

                    Layout.fillWidth: true
                    implicitHeight: 40
                    radius: Theme.radiusSm
                    color: mouse.containsMouse ? Theme.surface300 : isWindow && window.focused ? Theme.surface100 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2 + (line.modelData.indented ? 28 : 0)
                        anchors.rightMargin: Theme.space2
                        spacing: Theme.space2

                        IconImage {
                            implicitSize: line.isWindow ? 16 : 24
                            source: Apps.iconFor(line.modelData.app.key, line.modelData.app.icon)
                            opacity: line.isWindow || line.modelData.app.running ? 1 : 0.6
                        }

                        Rectangle {
                            visible: line.isWindow && !!line.window.tag
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: line.isWindow && line.window.tag ? Taskbar.tagColour(line.window.tag.color) : "transparent"
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: line.isWindow ? (line.window.title || "Untitled window") : line.modelData.app.name
                            color: line.isWindow && !line.window.focused ? Theme.inkMuted : Theme.ink
                        }

                        UiText {
                            text: line.isWindow ? (line.window.minimized ? "Minimised" : line.window.tag ? line.window.tag.name : "")
                                : line.modelData.app.windows.length === 0 ? "Not running"
                                : line.modelData.app.windows.length === 1 ? "1 window" : line.modelData.app.windows.length + " windows"
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: event => {
                            const app = line.modelData.app;
                            if (event.button === Qt.RightButton) {
                                const at = root.at(line, event.x);
                                Menus.open(at, line.isWindow ? Menus.windowItems(line.window, at) : Menus.appItems(app, at, root.isFolder ? root.item : null));
                                return;
                            }
                            ShellState.popover = null;
                            if (line.isWindow) Taskbar.focusWindow(line.window.hwnd);
                            else if (app.windows.length === 0) Apps.launchKey(app.key);
                            else Taskbar.focusWindow(app.windows[0].hwnd);
                        }
                    }
                }
            }
        }
    }
}
