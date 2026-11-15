// Control Panel: Personalisation. Colours, text, Home, the taskbar and how windows behave
// (what the old Settings window held).
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    readonly property var values: ShellSettings.values || ({ taskbar: {} })

    spacing: 0

    CpSection {
        title: "Look"

        CpRow {
            label: "Colours"
            hint: "For the desktop and apps"
            CpChoice {
                value: page.values.themeMode === "auto" ? "auto" : page.values.dark !== false ? "dark" : "light"
                options: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }, { value: "auto", label: "Match time of day" }]
                onPicked: value => ShellSettings.update(settings => {
                    settings.themeMode = value === "auto" ? "auto" : "";
                    if (value !== "auto") settings.dark = value === "dark";
                })
            }
        }

        CpRow {
            label: "Smoother text"
            hint: "Applies to apps you open after turning it on"
            ToggleSwitch {
                on: page.values.smoothText !== false
                onToggled: Desktop.setSmoothText(page.values.smoothText === false)
            }
        }

        CpRow {
            label: "Show Home on an empty desktop"
            hint: "Shows search and recent files when no windows are open"
            ToggleSwitch {
                on: page.values.showHome !== false
                onToggled: ShellSettings.set("showHome", page.values.showHome === false)
            }
        }
    }

    CpSection {
        title: "Taskbar"

        CpRow {
            label: "Show app names"
            hint: "Next to each icon on the taskbar"
            ToggleSwitch {
                on: page.values.taskbar.showLabels !== false
                onToggled: ShellSettings.setTaskbar("showLabels", page.values.taskbar.showLabels === false)
            }
        }

        CpRow {
            label: "Always auto-hide"
            hint: "Move the pointer to the bottom edge to show it"
            ToggleSwitch {
                on: !!page.values.taskbar.alwaysAutoHide
                onToggled: ShellSettings.setTaskbar("alwaysAutoHide", !page.values.taskbar.alwaysAutoHide)
            }
        }

        CpRow {
            label: "Auto-hide when a window is maximised"
            enabled: !page.values.taskbar.alwaysAutoHide
            ToggleSwitch {
                on: !!page.values.taskbar.autoHideWhenMaximised
                onToggled: ShellSettings.setTaskbar("autoHideWhenMaximised", !page.values.taskbar.autoHideWhenMaximised)
            }
        }
    }

    CpSection {
        title: "Windows"

        CpRow {
            label: "Tile windows"
            hint: "Arrange windows side by side. When off, they can overlap."
            ToggleSwitch {
                on: !!page.values.tiling
                onToggled: Taskbar.setTiling(!page.values.tiling)
            }
        }

        CpRow {
            label: "Snap to zones"
            hint: "Hold Shift while dragging a window. Add Ctrl to fill more than one zone."
            ToggleSwitch {
                on: Zones.enabled
                onToggled: Zones.setEnabled(!Zones.enabled)
            }
        }

        CpRow {
            label: "Window zones"
            hint: "Choose a layout or make your own"
            opens: true
            onClicked: ShellState.zoneEditorOpen = true
        }

        CpRow {
            label: "Remember where windows were"
            hint: "Apps open their windows in the same place and size as last time, maximised or in their zones."
            ToggleSwitch {
                on: WindowMemory.enabled
                enabled: !page.values.tiling
                onToggled: WindowMemory.setEnabled(!(page.values.rememberWindows !== false))
            }
        }

        // Apps whose extra title bar was hidden (the taskbar's right-click menu: Hide title bar).
        CpRow {
            visible: Taskbar.titleBarOff.length > 0
            label: "Apps without the desktop's title bar"
            hint: "They draw their own. Right-click an app on the taskbar to hide another's."

            below: [
                Repeater {
                    model: Taskbar.titleBarOff

                    RowLayout {
                        required property string modelData
                        Layout.fillWidth: true
                        spacing: Theme.space2

                        UiText {
                            Layout.fillWidth: true
                            text: Apps.nameFor(Apps.keyFor(parent.modelData))
                        }

                        PillButton {
                            text: "Show title bar"
                            onClicked: Taskbar.setTitleBar(parent.parent.modelData, true)
                        }
                    }
                }
            ]
        }

        CpRow {
            label: "Quick search (Alt+Space)"
            hint: "Open a small search box from any app"
            ToggleSwitch {
                on: page.values.paletteHotkey !== false
                onToggled: ShellSettings.set("paletteHotkey", page.values.paletteHotkey === false)
            }
        }
    }
}
