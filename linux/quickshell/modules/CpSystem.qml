// Control Panel: System. What the computer is and Graphite Desk's version, the way to its
// storage (CpStorage.qml), and a way to reload the desktop.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    spacing: 0

    CpSection {
        title: "About"

        CpRow {
            glyph: "computer-symbolic"
            label: Machine.about.host || "This computer"
            hint: Machine.about.model || ""
        }

        CpRow {
            label: "Processor"
            hint: (Machine.about.cpu || "") + (Machine.about.cores ? ", " + Machine.about.cores + " threads" : "")
        }

        CpRow {
            label: "Memory"
            hint: (Machine.about.memory || "?") + " GB"
        }

        CpRow {
            label: "Graphics"
            hint: (Machine.about.gpu || "").split(";").join("\n")
        }

        CpRow {
            label: "Graphite"
            hint: "Version " + (Machine.about.version || "?") + " on Arch Linux (kernel " + (Machine.about.kernel || "?") + ")"
        }
    }

    CpSection {
        title: "Storage"

        CpRow {
            glyph: "drive-harddisk-system-symbolic"
            label: "Storage and clean-up"
            hint: "What's taking up space on your drives, and what can go"
            opens: true
            onClicked: ShellState.settingsPage = "storage"
        }
    }

    CpSection {
        title: "Desktop"

        CpRow {
            label: "Reload the desktop"
            hint: "Restarts the taskbar and menus. Try this if something looks wrong."
            PillButton {
                text: "Reload"
                onClicked: Quickshell.reload(true)
            }
        }
    }
}
