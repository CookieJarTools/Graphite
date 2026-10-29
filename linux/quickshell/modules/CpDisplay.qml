// Control Panel: Display. For each screen: its resolution and refresh rate, scale, rotation,
// HDR, and on or off (a change waits 15 seconds to be kept, or goes back by itself); then
// brightness (a laptop's screen) and night light.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    spacing: 0

    Component.onCompleted: Displays.refresh()

    // Keep these display settings?
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: Displays.pending !== null
        implicitHeight: keepRow.implicitHeight + Theme.space3 * 2
        radius: Theme.radiusMd
        color: Theme.accentSoft
        border.color: Theme.accent
        border.width: 1

        RowLayout {
            id: keepRow
            x: Theme.space4
            y: Theme.space3
            width: parent.width - Theme.space4 * 2
            spacing: Theme.space2

            UiText {
                Layout.fillWidth: true
                text: "Keep these display settings? Going back in " + Displays.countdown + " s"
                font.weight: Font.DemiBold
            }

            PillButton {
                text: "Go back"
                onClicked: Displays.revert()
            }

            PillButton {
                primary: true
                text: "Keep"
                onClicked: Displays.keep()
            }
        }
    }

    Repeater {
        model: Displays.monitors

        CpSection {
            id: screenSection
            required property var modelData
            required property int index
            readonly property var choice: Displays.chosen[modelData.name] || {}

            title: Displays.monitors.length > 1 ? "Screen " + (index + 1) + ": " + modelData.description : modelData.description

            CpRow {
                label: "Resolution and refresh rate"
                hint: "Bigger numbers: sharper, and smoother"
                enabled: !screenSection.modelData.disabled

                CpChoice {
                    value: Displays.currentMode(screenSection.modelData)
                    options: screenSection.modelData.modes.map(mode => {
                        const parts = mode.split("@");
                        return { value: mode, label: parts[0].replace("x", " × ") + "  ·  " + Math.round(Number(parts[1])) + " Hz" };
                    })
                    onPicked: value => Displays.change(screenSection.modelData.name, "mode", value)
                }
            }

            CpRow {
                label: "Scale"
                hint: "Makes text, apps and the bar bigger"
                enabled: !screenSection.modelData.disabled

                CpChoice {
                    value: screenSection.modelData.scale
                    options: [1, 1.25, 1.5, 1.75, 2].map(scale => ({ value: scale, label: Math.round(scale * 100) + "%" }))
                    onPicked: value => Displays.change(screenSection.modelData.name, "scale", value)
                }
            }

            CpRow {
                label: "Rotation"
                enabled: !screenSection.modelData.disabled

                CpChoice {
                    value: screenSection.modelData.transform
                    options: [
                        { value: 0, label: "Landscape" },
                        { value: 1, label: "Portrait" },
                        { value: 2, label: "Landscape (upside down)" },
                        { value: 3, label: "Portrait (upside down)" }
                    ]
                    onPicked: value => Displays.change(screenSection.modelData.name, "transform", value)
                }
            }

            CpRow {
                label: "HDR"
                hint: "Brighter highlights and richer colour, for screens and games that support it"
                enabled: !screenSection.modelData.disabled

                ToggleSwitch {
                    on: !!screenSection.choice.hdr
                    onToggled: Displays.change(screenSection.modelData.name, "hdr", !screenSection.choice.hdr)
                }
            }

            CpRow {
                visible: Displays.monitors.length > 1
                label: "Use this screen"

                ToggleSwitch {
                    on: !screenSection.modelData.disabled
                    onToggled: Displays.change(screenSection.modelData.name, "enabled", screenSection.modelData.disabled)
                }
            }
        }
    }

    CpSection {
        title: "Brightness and colour"

        CpRow {
            visible: Displays.hasBacklight
            glyph: "display-brightness-symbolic"
            label: "Brightness"

            SliderBar {
                Layout.preferredWidth: 200
                value: Displays.brightness
                onMoved: value => Displays.setBrightness(value)
            }
        }

        CpRow {
            glyph: "night-light-symbolic"
            label: "Night light"
            hint: "Warmer colours, easier on the eyes in the evening"

            ToggleSwitch {
                on: Displays.nightLight
                onToggled: Displays.setNightLight(!Displays.nightLight)
            }

            below: [
                RowLayout {
                    Layout.fillWidth: true
                    visible: Displays.nightLight
                    spacing: Theme.space3

                    UiText {
                        text: "Warmth"
                        color: Theme.inkMuted
                    }

                    SliderBar {
                        Layout.fillWidth: true
                        // 6500 K (none) to 2500 K (very warm)
                        value: (6500 - Displays.warmth) / 4000
                        onMoved: value => Displays.setWarmth(Math.round(6500 - value * 4000))
                    }
                }
            ]
        }
    }
}
