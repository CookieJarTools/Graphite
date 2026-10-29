// Control Panel: Bluetooth & devices. Bluetooth (pair, connect, forget), the mouse and
// touchpad, the keyboard layout, and printers.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.config
import qs.services

ColumnLayout {
    id: page

    property bool shown: false
    readonly property var adapter: Bluetooth.defaultAdapter

    spacing: 0

    CpSection {
        CpRow {
            glyph: "bluetooth-active-symbolic"
            label: "Bluetooth"
            hint: !page.adapter ? "This computer has no Bluetooth" : page.adapter.enabled ? "On. Visible to nearby devices while this page is open." : "Off"
            enabled: page.adapter !== null

            ToggleSwitch {
                on: page.adapter !== null && page.adapter.enabled
                onToggled: { if (page.adapter) page.adapter.enabled = !page.adapter.enabled; }
            }

            below: [
                BluetoothList {
                    Layout.fillWidth: true
                    visible: page.adapter !== null && page.adapter.enabled
                    searching: page.shown
                }
            ]
        }
    }

    CpSection {
        title: "Mouse and touchpad"

        CpRow {
            label: "Pointer speed"

            SliderBar {
                Layout.preferredWidth: 200
                value: ((Displays.input.sensitivity ?? -0.4) + 1) / 2
                onMoved: value => Displays.setInput("sensitivity", Math.round((value * 2 - 1) * 20) / 20)
            }
        }

        CpRow {
            label: "Reverse the mouse wheel"
            hint: "Scroll the other way"

            ToggleSwitch {
                on: !!Displays.input.naturalScroll
                onToggled: Displays.setInput("naturalScroll", !Displays.input.naturalScroll)
            }
        }

        CpRow {
            label: "Touchpad: natural scrolling"
            hint: "The page moves with your fingers"

            ToggleSwitch {
                on: Displays.input.touchpadNaturalScroll !== false
                onToggled: Displays.setInput("touchpadNaturalScroll", Displays.input.touchpadNaturalScroll === false)
            }
        }

        CpRow {
            label: "Touchpad: tap to click"

            ToggleSwitch {
                on: Displays.input.tapToClick !== false
                onToggled: Displays.setInput("tapToClick", Displays.input.tapToClick === false)
            }
        }
    }

    CpSection {
        title: "Keyboard"

        CpRow {
            label: "Keyboard layout"
            hint: "The language your keyboard types in"

            CpChoice {
                value: (ShellSettings.values && ShellSettings.values.keyboard) || ""
                options: [
                    { value: "", label: "Same as during install" },
                    { value: "gb", label: "English (UK)" }, { value: "us", label: "English (US)" },
                    { value: "ie", label: "English (Ireland)" }, { value: "de", label: "German" },
                    { value: "fr", label: "French" }, { value: "es", label: "Spanish" },
                    { value: "it", label: "Italian" }, { value: "nl", label: "Dutch" },
                    { value: "se", label: "Swedish" }, { value: "no", label: "Norwegian" },
                    { value: "dk", label: "Danish" }, { value: "fi", label: "Finnish" },
                    { value: "pl", label: "Polish" }, { value: "pt", label: "Portuguese" },
                    { value: "br", label: "Portuguese (Brazil)" }, { value: "ch", label: "Swiss" },
                    { value: "be", label: "Belgian" }
                ]
                onPicked: value => Displays.setKeyboard(value)
            }
        }
    }

    CpSection {
        title: "Printers"

        CpRow {
            glyph: "printer-symbolic"
            label: "Printers and scanners"
            hint: "Add a printer or scanner"
            opens: true
            onClicked: Quickshell.execDetached(["system-config-printer"])
        }
    }
}
