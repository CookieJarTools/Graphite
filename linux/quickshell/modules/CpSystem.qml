// Control Panel: System. What the computer is, its storage (with a clean-up), and Graphite
// Desk's version; and a way to reload the desktop.
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

        Repeater {
            model: Machine.storage

            CpRow {
                id: diskRow
                required property var modelData
                glyph: "drive-harddisk-symbolic"
                label: modelData.mount === "/" ? "This computer" : modelData.mount
                hint: Machine.size(modelData.free) + " free of " + Machine.size(modelData.size)

                below: [
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.surface300

                        Rectangle {
                            width: parent.width * diskRow.modelData.percent
                            height: parent.height
                            radius: 3
                            color: diskRow.modelData.percent > 0.9 ? Theme.danger : Theme.accent
                        }
                    }
                ]
            }
        }

        CpRow {
            glyph: "edit-clear-all-symbolic"
            label: "Free up space"
            hint: "Deletes old updates and other temporary files. Your files are safe."
            PillButton {
                text: Machine.cleaning ? "Cleaning..." : "Clean up"
                enabled: !Machine.cleaning
                onClicked: Machine.clean()
            }
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
