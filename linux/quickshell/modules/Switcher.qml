// Alt+Tab: the windows, most recently used first, each as a live preview. Tab moves on,
// Shift+Tab back; letting go of Alt switches (hyprland.lua binds these to Shortcuts.qml).
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
        if (chosen) chosen.activate();
    }

    function cancel() {
        open = false;
        windows = [];
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
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(cards.implicitWidth, root.width - Theme.space10 * 2) + Theme.space4 * 2
        height: cards.implicitHeight + Theme.space4 * 2
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1

        Flow {
            id: cards

            anchors.centerIn: parent
            width: Math.min(root.windows.length * 236, root.width - Theme.space10 * 2)
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

                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: root.open ? card.modelData : null
                                live: root.open
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            IconImage {
                                implicitSize: 16
                                source: Apps.iconOf(Apps.build([card.modelData], [])[0])
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: card.modelData.title
                                font.pixelSize: Theme.hintSize
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
