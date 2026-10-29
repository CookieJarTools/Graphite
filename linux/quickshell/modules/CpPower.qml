// Control Panel: Power & battery. The battery, the power mode, and what happens when the
// computer is left alone (lock, screen off, sleep).
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.config
import qs.services

ColumnLayout {
    id: page

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isLaptopBattery && battery.isPresent
    readonly property var minutes: [
        { value: 1, label: "1 minute" }, { value: 2, label: "2 minutes" }, { value: 5, label: "5 minutes" },
        { value: 10, label: "10 minutes" }, { value: 15, label: "15 minutes" }, { value: 30, label: "30 minutes" },
        { value: 60, label: "1 hour" }, { value: 0, label: "Never" }
    ]

    spacing: 0

    Component.onCompleted: Power.refresh()

    CpSection {
        visible: page.hasBattery

        CpRow {
            glyph: page.battery ? (page.battery.iconName || "battery-good-symbolic") : ""
            label: page.hasBattery ? "Battery " + Math.round(page.battery.percentage * (page.battery.percentage <= 1 ? 100 : 1)) + "%" : ""
            hint: !page.hasBattery ? "" : UPower.onBattery
                ? (page.battery.timeToEmpty > 0 ? "About " + Math.round(page.battery.timeToEmpty / 60) + " minutes left" : "On battery")
                : "Plugged in" + (page.battery.timeToFull > 0 ? ", full in about " + Math.round(page.battery.timeToFull / 60) + " minutes" : "")
        }
    }

    CpSection {
        title: "Power mode"

        CpRow {
            label: "Power mode"
            hint: "Save power for longer battery life, or choose best performance for games"

            CpChoice {
                value: Power.profile
                options: Power.profiles.map(name => ({ value: name, label: ({ "power-saver": "Save power", "balanced": "Balanced", "performance": "Best performance" })[name] }))
                onPicked: value => Power.setProfile(value)
            }
        }
    }

    CpSection {
        title: "When the computer is idle"

        CpRow {
            label: "Lock after"
            hint: "You'll need your password to unlock"

            CpChoice {
                value: Power.idle.lock === undefined ? 10 : Power.idle.lock
                options: page.minutes
                onPicked: value => Power.setIdle("lock", value)
            }
        }

        CpRow {
            label: "Turn off the screen after"

            CpChoice {
                value: Power.idle.screenOff === undefined ? 15 : Power.idle.screenOff
                options: page.minutes
                onPicked: value => Power.setIdle("screenOff", value)
            }
        }

        CpRow {
            label: "Sleep after"
            hint: "Your open apps stay open while it sleeps"

            CpChoice {
                value: Power.idle.sleep === undefined ? 30 : Power.idle.sleep
                options: page.minutes
                onPicked: value => Power.setIdle("sleep", value)
            }
        }
    }
}
