// Task view (Super+Tab, as on Windows): every window on the desktop being shown, as live
// previews over a dimmed screen; a click goes to one, its × closes it. Below, the desktops
// (Hyprland's workspaces) with how many windows each has: a click shows that one, "New
// desktop" opens an empty one. Escape, Super+Tab or a click on the background closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    readonly property bool open: ShellState.taskViewOpen
    readonly property var monitor: Hyprland.focusedMonitor
    property int shownDesktop: 1

    screen: {
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => monitor && candidate.name === monitor.name) || screens[0];
    }
    visible: open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-taskview"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: if (open) {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        shownDesktop = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : 1;
        keys.forceActiveFocus();
    }

    // Desktops with windows, and the one shown, in order.
    readonly property var desktops: {
        const ids = Array.from(Hyprland.workspaces.values).map(workspace => workspace.id).filter(id => id > 0);
        if (!ids.includes(shownDesktop)) ids.push(shownDesktop);
        return ids.sort((first, second) => first - second);
    }
    readonly property var windows: Array.from(Hyprland.toplevels.values)
        .filter(toplevel => toplevel.workspace && toplevel.workspace.id === shownDesktop)

    function countOn(id) {
        return Array.from(Hyprland.toplevels.values).filter(toplevel => toplevel.workspace && toplevel.workspace.id === id).length;
    }

    function goTo(toplevel) {
        ShellState.taskViewOpen = false;
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${Taskbar.addressOf(toplevel)}" })`);
    }

    function showDesktop(id) {
        shownDesktop = id;
        Hyprland.dispatch(`hl.dsp.focus({ workspace = "${id}" })`);
    }

    // The first desktop number not in use.
    function newDesktop() {
        const used = Array.from(Hyprland.workspaces.values).map(workspace => workspace.id);
        let id = 1;
        while (used.includes(id)) id++;
        showDesktop(id);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.taskViewOpen = false
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: root.open
        Keys.onEscapePressed: ShellState.taskViewOpen = false

        // ---------- the windows ----------

        GridLayout {
            id: grid
            readonly property int count: Math.max(1, root.windows.length)
            readonly property int cols: Math.min(count, Math.ceil(Math.sqrt(count * 1.6)))
            readonly property int rows: Math.ceil(count / cols)
            readonly property real cardWidth: Math.min(420, (parent.width * 0.86 - (cols - 1) * Theme.space6) / cols)
            readonly property real cardHeight: Math.min(cardWidth * 0.72, (parent.height - 280 - (rows - 1) * Theme.space6) / rows)

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -60
            columns: cols
            columnSpacing: Theme.space6
            rowSpacing: Theme.space6

            Repeater {
                model: root.open ? root.windows : []

                Rectangle {
                    id: card
                    required property var modelData
                    readonly property var info: modelData.lastIpcObject || ({})
                    Layout.preferredWidth: grid.cardWidth
                    Layout.preferredHeight: grid.cardHeight + 36
                    radius: Theme.radiusMd
                    color: cardMouse.containsMouse ? Theme.surface300 : Theme.surface200
                    border.color: cardMouse.containsMouse ? Theme.accent : Theme.glassEdge
                    border.width: cardMouse.containsMouse ? 2 : 1

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: event => {
                            if (event.button === Qt.MiddleButton) Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${Taskbar.addressOf(card.modelData)}" })`);
                            else root.goTo(card.modelData);
                        }
                    }

                    RowLayout {
                        x: Theme.space3
                        y: 0
                        width: parent.width - Theme.space3 * 2
                        height: 36
                        spacing: Theme.space2

                        IconImage {
                            implicitSize: 18
                            source: Quickshell.iconPath(String(card.info.class || "").toLowerCase(), "application-x-executable")
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: card.modelData.title || card.info.class || ""
                            font.weight: Font.Medium
                        }

                        BarButton {
                            implicitWidth: 26
                            implicitHeight: 26
                            visible: cardMouse.containsMouse
                            glyph: "window-close-symbolic"
                            onClicked: Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${Taskbar.addressOf(card.modelData)}" })`)
                        }
                    }

                    Rectangle {
                        x: Theme.space2
                        y: 36
                        width: parent.width - Theme.space2 * 2
                        height: parent.height - 36 - Theme.space2
                        radius: Theme.radiusSm
                        color: Theme.surface100
                        clip: true

                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: root.open && card.modelData.wayland ? card.modelData.wayland : null
                            live: true
                            constraintSize: Qt.size(width, height)
                        }
                    }
                }
            }
        }

        UiText {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -60
            visible: root.windows.length === 0
            text: "No windows on this desktop"
            color: Theme.inkMuted
            font.pixelSize: 18
        }

        // ---------- the desktops ----------

        RowLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.taskbarHeight + Theme.space10
            spacing: Theme.space3

            Repeater {
                model: root.open ? root.desktops : []

                Rectangle {
                    id: desktop
                    required property int modelData
                    readonly property bool shown: modelData === root.shownDesktop
                    implicitWidth: 150
                    implicitHeight: 64
                    radius: Theme.radiusMd
                    color: shown ? Theme.accentSoft : desktopMouse.containsMouse ? Theme.surface300 : Theme.surface200
                    border.color: shown ? Theme.accent : Theme.glassEdge
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Desktop " + desktop.modelData
                            font.weight: Font.DemiBold
                        }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            readonly property int count: root.countOn(desktop.modelData)
                            text: count === 0 ? "Empty" : count === 1 ? "1 window" : count + " windows"
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                    }

                    MouseArea {
                        id: desktopMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.showDesktop(desktop.modelData)
                    }
                }
            }

            Rectangle {
                implicitWidth: 150
                implicitHeight: 64
                radius: Theme.radiusMd
                color: newMouse.containsMouse ? Theme.surface300 : "transparent"
                border.color: Theme.lineStrong
                border.width: 1

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    Glyph { name: "list-add-symbolic" }
                    UiText { text: "New desktop" }
                }

                MouseArea {
                    id: newMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.newDesktop()
                }
            }
        }
    }
}
