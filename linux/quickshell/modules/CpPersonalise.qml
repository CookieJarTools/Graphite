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
            hint: "The desktop's and the apps' colours"
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
            hint: "Fuller, smoother letters in every app (like MacType); apps opened from now on"
            ToggleSwitch {
                on: page.values.smoothText !== false
                onToggled: Desktop.setSmoothText(page.values.smoothText === false)
            }
        }

        CpRow {
            label: "Home on an empty screen"
            hint: "Search and Recent on the backdrop whenever a workspace has no windows"
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
            hint: "Next to each icon on the bar"
            ToggleSwitch {
                on: page.values.taskbar.showLabels !== false
                onToggled: ShellSettings.setTaskbar("showLabels", page.values.taskbar.showLabels === false)
            }
        }

        CpRow {
            label: "Always auto-hide"
            hint: "The bar slides away; touch the bottom edge to bring it back"
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
            hint: "Windows fill the screen side by side; off, they float and overlap as on Windows"
            ToggleSwitch {
                on: !!page.values.tiling
                onToggled: Taskbar.setTiling(!page.values.tiling)
            }
        }

        CpRow {
            label: "Snap to zones"
            hint: "Hold Shift while dragging a window to drop it into a zone; with Ctrl, it fills several"
            ToggleSwitch {
                on: Zones.enabled
                onToggled: Zones.setEnabled(!Zones.enabled)
            }
        }

        CpRow {
            label: "Window zones"
            hint: "Pick a layout, or split and size the zones yourself"
            opens: true
            onClicked: {
                ShellState.settingsOpen = false;
                ShellState.zoneEditorOpen = true;
            }
        }

        CpRow {
            label: "Alt+Space search"
            hint: "A compact search over everything, from any app"
            ToggleSwitch {
                on: page.values.paletteHotkey !== false
                onToggled: ShellSettings.set("paletteHotkey", page.values.paletteHotkey === false)
            }
        }
    }
}
