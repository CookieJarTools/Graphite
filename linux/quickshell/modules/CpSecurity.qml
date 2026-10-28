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
                ? "On: nothing from the network can reach this computer unless it asked for it"
                : "Off: turn it on, especially on public Wi-Fi"
            enabled: Machine.about.hasFirewall === "yes"

            ToggleSwitch {
                on: Machine.about.firewall === "on"
                onToggled: Machine.setFirewall(Machine.about.firewall !== "on")
            }
        }

        CpRow {
            glyph: "system-lock-screen-symbolic"
            label: "Lock the screen"
            hint: "Super+L locks it now; it also locks by itself when you leave it (Power & battery) and before sleeping"
            PillButton {
                text: "Lock now"
                onClicked: ShellState.locked = true
            }
        }

        CpRow {
            glyph: "drive-harddisk-system-symbolic"
            label: "Disk encryption"
            hint: Number(Machine.about.encrypted || 0) > 0
                ? "On: without your password, the disk can't be read even if it's taken out"
                : "Off. Encryption is chosen when installing."
        }
    }

    CpSection {
        title: "Privacy"

        CpRow {
            glyph: "find-location-symbolic"
            label: "App permissions"
            hint: "Apps from Flathub each ask before using the camera, microphone, location or your files"
        }
    }
}
