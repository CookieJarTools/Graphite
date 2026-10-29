// Control Panel: Privacy & security. The firewall, locking, and whether the disk is encrypted.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    spacing: 0

    CpSection {
        CpRow {
            glyph: "security-high-symbolic"
            label: "Firewall"
            hint: Machine.about.hasFirewall !== "yes" ? "Not installed" : Machine.about.firewall === "on"
                ? "On. Blocks unwanted connections from the network."
                : "Off. Turn it on, especially on public Wi-Fi."
            enabled: Machine.about.hasFirewall === "yes"

            ToggleSwitch {
                on: Machine.about.firewall === "on"
                onToggled: Machine.setFirewall(Machine.about.firewall !== "on")
            }
        }

        CpRow {
            glyph: "system-lock-screen-symbolic"
            label: "Lock the screen"
            hint: "Press Windows key + L. It also locks when idle and before sleep."
            PillButton {
                text: "Lock now"
                onClicked: ShellState.locked = true
            }
        }

        CpRow {
            glyph: "drive-harddisk-system-symbolic"
            label: "Disk encryption"
            hint: Number(Machine.about.encrypted || 0) > 0
                ? "On. The disk can't be read without your password."
                : "Off. You can only turn this on during install."
        }
    }

    CpSection {
        title: "Privacy"

        CpRow {
            glyph: "find-location-symbolic"
            label: "App permissions"
            hint: "Flathub apps ask before using your camera, microphone, location or files"
        }
    }
}
