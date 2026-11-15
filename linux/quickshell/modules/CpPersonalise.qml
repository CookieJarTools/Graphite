// Control Panel: Personalisation. Colours and the accent, motion, blur, the wallpaper, text,
// Home, the taskbar and how windows behave (what the old Settings window held).
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    readonly property var values: ShellSettings.values || ({ taskbar: {} })

    spacing: 0

    CpSection {
        title: "Appearance"

        CpRow {
            label: "Theme"
            hint: "For the desktop and apps. Auto is light from 7 in the morning to 7 in the evening."
            CpSegments {
                value: page.values.themeMode === "auto" ? "auto" : page.values.dark !== false ? "dark" : "light"
                options: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }, { value: "auto", label: "Auto" }]
                onPicked: value => ShellSettings.update(settings => {
                    settings.themeMode = value === "auto" ? "auto" : "";
                    if (value !== "auto") settings.dark = value === "dark";
                })
            }
        }

        CpRow {
            label: "Accent"
            hint: Theme.accentSet.name + ": indicators, selection and buttons"

            // The accents as 24 px swatches; the chosen one is ringed and a little larger.
            Row {
                spacing: Theme.space2

                Repeater {
                    model: Theme.accentNames

                    Item {
                        id: swatch
                        required property string modelData
                        readonly property bool chosen: Theme.accentName === modelData
                        width: 30
                        height: 30
                        scale: chosen ? Theme.grow(1.08) : 1
                        Behavior on scale { NumberAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

                        Accessible.role: Accessible.RadioButton
                        Accessible.name: Theme.accents[modelData].name
                        Accessible.checked: chosen
                        Accessible.onPressAction: Look.setAccent(modelData)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: 15
                            color: "transparent"
                            border.color: Theme.ink
                            border.width: 2
                            visible: swatch.chosen
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            radius: 12
                            color: Theme.accents[swatch.modelData].accent
                            opacity: swatchMouse.containsMouse || swatch.chosen ? 1 : 0.85
                        }

                        MouseArea {
                            id: swatchMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Look.setAccent(swatch.modelData)
                        }
                    }
                }
            }
        }

        CpRow {
            label: "Window animations"
            hint: "Off, windows and the desktop only fade, briefly"
            ToggleSwitch {
                on: Look.windowAnimations
                onToggled: Look.setWindowAnimations(!Look.windowAnimations)
            }
        }

        CpRow {
            label: "Auto-hide taskbar"
            hint: "It slides away; touch the bottom edge to bring it back"
            ToggleSwitch {
                on: !!page.values.taskbar.alwaysAutoHide
                onToggled: ShellSettings.setTaskbar("alwaysAutoHide", !page.values.taskbar.alwaysAutoHide)
            }
        }

        CpRow {
            label: "Background blur"
            hint: "Blur behind the taskbar, toasts and the launcher. Off, they turn solid."
            ToggleSwitch {
                on: Look.blur
                onToggled: Look.setBlur(!Look.blur)
            }
        }

        CpRow {
            label: "Animation speed"
            hint: "How quickly things open, close and move"

            RowLayout {
                spacing: Theme.space3

                SliderBar {
                    Layout.preferredWidth: 200
                    value: (Look.speed - 0.5) / 1
                    onMoved: value => {
                        const speed = Math.round((0.5 + value) * 4) / 4;
                        if (speed !== Look.speed) Look.setSpeed(speed);
                    }
                }

                UiText {
                    Layout.preferredWidth: 40
                    horizontalAlignment: Text.AlignRight
                    text: String(Look.speed) + "×"
                    color: Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                }
            }
        }

        CpRow {
            label: "Live wallpaper"
            hint: "The glow drifts slowly while no window is open"
            enabled: Look.windowAnimations
            ToggleSwitch {
                on: Look.liveWallpaper
                onToggled: Look.setLiveWallpaper(!Look.liveWallpaper)
            }
        }
    }

    CpSection {
        title: "Text and Home"

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
