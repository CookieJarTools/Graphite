// Alt+Tab: the windows, most recently used first, each as a live preview with its app's
// launcher alias. Tab (or the arrows) moves on, Shift+Tab back; letting go of Alt or Enter
// switches, W closes the picked window, Escape or a click beside the cards cancels
// (hyprland.lua binds the Alt+Tab keys to Shortcuts.qml; the rest arrive here).
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

    property bool open: false
    property var windows: []
    property int index: 0

    // Tab: open on the window before this one, or move on.
    function step(delta) {
        if (!open) {
            windows = ShellState.windowsByRecency();
            if (windows.length === 0) return;
            index = windows.length > 1 ? (delta > 0 ? 1 : windows.length - 1) : 0;
            open = true;
            return;
        }
        index = (index + delta + windows.length) % windows.length;
    }

    function commit() {
        if (!open) return;
        const chosen = windows[index];
        open = false;
        windows = [];
        if (!chosen) return;
        // A minimised window comes back from where it waits.
        const hwnd = addressOf(chosen);
        if (hwnd) Taskbar.focusWindow(hwnd);
        else chosen.activate();
    }

    function cancel() {
        open = false;
        windows = [];
    }

    // W: close the picked window; the list catches up once it has gone.
    function closePicked() {
        const chosen = windows[index];
        if (chosen) chosen.close();
        afterClose.restart();
    }

    Timer {
        id: afterClose
        interval: 300
        onTriggered: {
            const open = ShellState.windowsByRecency();
            root.windows = root.windows.filter(window => open.includes(window));
            if (root.windows.length === 0) root.cancel();
            else root.index = Math.min(root.index, root.windows.length - 1);
        }
    }

    // A Wayland window's Hyprland address, and whether it is minimised (Taskbar.qml).
    function addressOf(toplevel) {
        const match = Array.from(Hyprland.toplevels.values).find(candidate => candidate.wayland === toplevel);
        return match ? Taskbar.addressOf(match) : "";
    }

    function minimised(toplevel) {
        const window = Taskbar.windowFor(addressOf(toplevel));
        return window !== null && window.minimized;
    }

    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    onOpenChanged: if (open) keys.forceActiveFocus()

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_W) root.closePicked();
            else if (event.key === Qt.Key_Escape) root.cancel();
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) root.step(1);
            else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) root.step(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit();
            else return;
            event.accepted = true;
        }
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt) root.commit();
        }
    }

    screen: {
        const focused = Hyprland.focusedMonitor;
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => focused && candidate.name === focused.name) || screens[0];
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
    WlrLayershell.namespace: "graphite-switcher"

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(cards.implicitWidth, root.width - Theme.space10 * 2) + Theme.space4 * 2
        height: cards.implicitHeight + Theme.space4 * 2
        radius: Theme.radiusLg
        color: Theme.glass(Theme.panel, 0.94)
        border.color: Theme.glassEdge
        border.width: 1

        Flow {
            id: cards

            anchors.centerIn: parent
            // Up to five cards a row.
            width: Math.min(Math.min(root.windows.length, 5) * 236, root.width - Theme.space10 * 2)
            spacing: Theme.space2

            Repeater {
                model: root.windows

                Rectangle {
                    id: card

                    required property var modelData
                    required property int index
                    readonly property bool chosen: index === root.index
                    width: 228
                    height: 180
                    radius: Theme.radiusMd
                    color: chosen ? Theme.surface300 : "transparent"
                    border.color: chosen ? Theme.accent : "transparent"
                    border.width: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space2
                        spacing: Theme.space2

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSm
                            color: Theme.surface100
                            clip: true

                            readonly property bool minimised: root.open && root.minimised(card.modelData)

                            ScreencopyView {
                                anchors.fill: parent
                                visible: !parent.minimised
                                captureSource: root.open && !parent.minimised ? card.modelData : null
                                live: root.open
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: parent.minimised
                                spacing: Theme.space1

                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 32
                                    source: Apps.iconFor(Apps.keyFor(card.modelData.appId), card.modelData.appId)
                                }

                                UiText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Minimised"
                                    color: Theme.inkMuted
                                    font.pixelSize: Theme.hintSize
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            IconImage {
                                implicitSize: 16
                                source: Apps.iconFor(Apps.keyFor(card.modelData.appId), card.modelData.appId)
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                font.pixelSize: Theme.hintSize
                            }

                            UiText {
                                text: Search.aliasOf(Apps.keyFor(card.modelData.appId))
                                color: Theme.inkMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.identifierSize
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.index = card.index;
                            root.commit();
                        }
                    }
                }
            }
        }
    }
}
