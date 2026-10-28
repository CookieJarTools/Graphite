// Graphite Desk's settings: a window of switches (a click anywhere on a row flips it), kept
// in settings.json. Opened from the bar's menu ("Taskbar settings"), the launcher's
// "Graphite settings", or `qs -c graphite ipc call settings open`; Escape closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

FloatingWindow {
    id: root

    visible: ShellState.settingsOpen
    title: "Graphite Desk settings"
    implicitWidth: 640
    implicitHeight: 720
    minimumSize: Qt.size(480, 400)
    color: Theme.surface100

    onVisibleChanged: if (!visible) ShellState.settingsOpen = false

    readonly property var values: ShellSettings.values || ({ taskbar: {} })

    readonly property var sections: [
        {
            title: "Start and search",
            rows: [
                { id: "palette", label: "Alt+Space search", hint: "A compact search over everything, from any app", on: values.paletteHotkey !== false, set: on => ShellSettings.set("paletteHotkey", on) }
            ]
        },
        {
            title: "Windows",
            rows: [
                { id: "tiling", label: "Tile windows", hint: "Windows fill the screen side by side; off, they float and overlap as on Windows", on: !!values.tiling, set: on => Taskbar.setTiling(on) },
                { id: "zones", label: "Snap to zones", hint: "Hold Shift while dragging a window to drop it into a zone; near a line, or with Ctrl, it fills several", on: Zones.enabled, set: on => Zones.setEnabled(on) },
                { id: "editZones", label: "Window zones", hint: "Pick a layout, or split and size the zones yourself", action: "Edit", run: () => { ShellState.settingsOpen = false; ShellState.zoneEditorOpen = true; } }
            ]
        },
        {
            title: "Desktop",
            rows: [
                { id: "home", label: "Home on an empty screen", hint: "Search and Recent on the backdrop whenever a workspace has no windows", on: values.showHome !== false, set: on => ShellSettings.set("showHome", on) },
                { id: "dark", label: "Dark mode", hint: "The shell's and the apps' colours; the light set otherwise", on: values.dark !== false, set: on => ShellSettings.set("dark", on) },
                { id: "smoothText", label: "Smoother text (like MacType)", hint: "Fuller, smoother letters in every app; apps opened from now on", on: values.smoothText !== false, set: on => Desktop.setSmoothText(on) }
            ]
        },
        {
            title: "Apps and games",
            rows: [
                { id: "apps", label: "Apps", hint: "Everything installed, to open or uninstall; and more apps with one click. Downloaded .deb, AppImage and Flatpak files install themselves when opened.", action: "Open", run: () => { ShellState.settingsOpen = false; Desktop.openApps(); } },
                { id: "gaming", label: "Set up gaming", hint: "Graphics drivers for this computer, Steam, Minecraft (Prism Launcher, tuned for modpacks), GameMode and an FPS overlay", action: "Set up", run: () => Desktop.setUpGaming() }
            ]
        },
        {
            title: "Taskbar",
            rows: [
                { id: "showLabels", label: "Show app names", hint: "Next to each icon on the bar", on: values.taskbar.showLabels !== false, set: on => ShellSettings.setTaskbar("showLabels", on) },
                { id: "alwaysAutoHide", label: "Always auto-hide", hint: "The bar slides away; touch the bottom edge to bring it back", on: !!values.taskbar.alwaysAutoHide, set: on => ShellSettings.setTaskbar("alwaysAutoHide", on) },
                { id: "autoHideWhenMaximised", label: "Auto-hide when a window is maximised", hint: "Only while the focused window fills the screen", on: !!values.taskbar.autoHideWhenMaximised, enabled: !values.taskbar.alwaysAutoHide, set: on => ShellSettings.setTaskbar("autoHideWhenMaximised", on) }
            ]
        }
    ]

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.settingsOpen = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: Theme.space6
                Layout.rightMargin: Theme.space3

                UiText {
                    Layout.fillWidth: true
                    text: "Settings"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                BarButton {
                    glyph: "window-close-symbolic"
                    onClicked: ShellState.settingsOpen = false
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: content.implicitHeight + Theme.space6
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: content
                    x: Theme.space6
                    width: parent.width - Theme.space6 * 2
                    spacing: Theme.space2

                    Repeater {
                        model: root.sections

                        ColumnLayout {
                            id: section
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.space4
                            spacing: Theme.space1

                            UiText {
                                text: section.modelData.title
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                                font.weight: Font.DemiBold
                            }

                            Repeater {
                                model: section.modelData.rows

                                Rectangle {
                                    id: row
                                    required property var modelData
                                    readonly property bool enabled: modelData.enabled !== false
                                    Layout.fillWidth: true
                                    implicitHeight: 64
                                    radius: Theme.radiusMd
                                    color: rowMouse.containsMouse && enabled ? Theme.surface300 : Theme.surface200
                                    border.color: Theme.line
                                    border.width: 1
                                    opacity: enabled ? 1 : 0.5

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.space4
                                        anchors.rightMargin: Theme.space4
                                        spacing: Theme.space4

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            UiText {
                                                Layout.fillWidth: true
                                                text: row.modelData.label
                                                font.weight: Font.Medium
                                            }

                                            UiText {
                                                Layout.fillWidth: true
                                                text: row.modelData.hint
                                                color: Theme.inkMuted
                                                font.pixelSize: Theme.hintSize
                                            }
                                        }

                                        // A row that does something: its button.
                                        Rectangle {
                                            visible: !!row.modelData.action
                                            implicitWidth: actionLabel.implicitWidth + Theme.space4 * 2
                                            implicitHeight: 32
                                            radius: Theme.radiusSm
                                            color: rowMouse.containsMouse ? Theme.accent : Theme.surface300
                                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                                            UiText {
                                                id: actionLabel
                                                anchors.centerIn: parent
                                                text: row.modelData.action || ""
                                                color: rowMouse.containsMouse ? Theme.onAccent : Theme.ink
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        // The switch.
                                        Rectangle {
                                            visible: !row.modelData.action
                                            implicitWidth: 40
                                            implicitHeight: 22
                                            radius: 11
                                            color: row.modelData.on ? Theme.accent : Theme.surface100
                                            border.color: row.modelData.on ? Theme.accent : Theme.lineStrong
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                                            Rectangle {
                                                width: 16
                                                height: 16
                                                radius: 8
                                                y: 3
                                                x: row.modelData.on ? parent.width - width - 3 : 3
                                                color: row.modelData.on ? Theme.onAccent : Theme.inkMuted
                                                Behavior on x { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeStandard } }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: row.enabled
                                        onClicked: {
                                            if (row.modelData.run) row.modelData.run();
                                            else row.modelData.set(!row.modelData.on);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.line
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: Theme.space6
                Layout.rightMargin: Theme.space4

                UiText {
                    Layout.fillWidth: true
                    text: "Graphite Desk for Linux"
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }

                MenuRow {
                    text: "Reload the shell"
                    onClicked: Quickshell.reload(true)
                }
            }
        }
    }
}
