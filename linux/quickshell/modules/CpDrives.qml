// Control Panel: Drives. Every drive and USB stick, its parts and how full they are: open,
// connect or disconnect them, eject a USB stick, format a part or erase a whole drive. The
// drive Graphite Desk runs from is shown but can't be formatted or erased.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    property bool shown: false
    property string form: ""      // the part (format) or drive (erase) whose form is open
    property bool confirming: false

    readonly property var filesystems: [
        { value: "exfat", label: "Most devices (exFAT)" },
        { value: "ntfs", label: "Windows (NTFS)" },
        { value: "fat32", label: "Older devices (FAT32)" },
        { value: "ext4", label: "Linux only (ext4)" }
    ]

    spacing: 0

    Binding {
        target: Drives
        property: "watching"
        value: page.shown
    }

    UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: Drives.message.length > 0
        text: Drives.message
        color: Theme.inkMuted
    }

    Repeater {
        model: Drives.disks

        CpSection {
            id: diskSection
            required property var modelData
            title: modelData.model + "  ·  " + Drives.size(modelData.size) + (modelData.system ? "  ·  System drive" : "")

            // The drive itself.
            CpRow {
                glyph: diskSection.modelData.removable ? "drive-removable-media-symbolic" : "drive-harddisk-symbolic"
                label: diskSection.modelData.parts.length === 0 ? "Empty drive" : diskSection.modelData.parts.length === 1 ? "1 partition" : diskSection.modelData.parts.length + " partitions"
                hint: diskSection.modelData.path

                PillButton {
                    visible: diskSection.modelData.removable && !diskSection.modelData.system
                    text: "Eject"
                    enabled: !Drives.busy
                    onClicked: Drives.eject(diskSection.modelData)
                }

                PillButton {
                    visible: !diskSection.modelData.system && page.form !== diskSection.modelData.path
                    danger: true
                    text: "Erase drive"
                    onClicked: {
                        page.confirming = false;
                        page.form = diskSection.modelData.path;
                    }
                }

                below: [
                    WipeForm {
                        Layout.fillWidth: true
                        visible: page.form === diskSection.modelData.path
                        warning: "This deletes everything on " + diskSection.modelData.model + "."
                        action: "Erase"
                        onConfirmed: (fs, label) => Drives.erase(diskSection.modelData.path, fs, label)
                    }
                ]
            }

            // Its parts.
            Repeater {
                model: diskSection.modelData.parts

                CpRow {
                    id: partRow
                    required property var modelData
                    glyph: "drive-harddisk-symbolic"
                    label: (modelData.name || modelData.fs || "Partition") + "  ·  " + Drives.size(modelData.size)
                    hint: (modelData.mount ? (modelData.used ? Drives.size(modelData.size - modelData.used) + " free · " : "") + "Connected at " + modelData.mount : "Not connected")
                        + (modelData.fs ? " · " + modelData.fs : "")

                    PillButton {
                        visible: partRow.modelData.mount.length > 0
                        text: "Open"
                        onClicked: Drives.open(partRow.modelData.mount)
                    }

                    PillButton {
                        visible: !diskSection.modelData.system && partRow.modelData.fs && partRow.modelData.fs !== "encrypted"
                        text: partRow.modelData.mount ? "Disconnect" : "Connect"
                        enabled: !Drives.busy
                        onClicked: partRow.modelData.mount ? Drives.unmount(partRow.modelData.path) : Drives.mount(partRow.modelData.path)
                    }

                    PillButton {
                        visible: !diskSection.modelData.system && page.form !== partRow.modelData.path
                        text: "Format"
                        onClicked: {
                            page.confirming = false;
                            page.form = partRow.modelData.path;
                        }
                    }

                    below: [
                        WipeForm {
                            Layout.fillWidth: true
                            visible: page.form === partRow.modelData.path
                            warning: "This deletes everything on this partition."
                            action: "Format"
                            onConfirmed: (fs, label) => Drives.format(partRow.modelData.path, fs, label)
                        }
                    ]

                    // How full it is.
                    Rectangle {
                        visible: partRow.modelData.mount.length > 0 && partRow.modelData.used > 0
                        implicitWidth: 120
                        implicitHeight: 6
                        radius: 3
                        color: Theme.surface300

                        Rectangle {
                            width: parent.width * Math.min(1, partRow.modelData.used / Math.max(1, partRow.modelData.size))
                            height: parent.height
                            radius: 3
                            color: partRow.modelData.used / partRow.modelData.size > 0.9 ? Theme.danger : Theme.accent
                        }
                    }
                }
            }
        }
    }

    // Format or erase: the kind of drive, a name, and a second press to be sure.
    component WipeForm: ColumnLayout {
        id: wipe

        property string warning
        property string action
        property string fs: "exfat"
        signal confirmed(string fs, string label)

        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            UiText {
                Layout.fillWidth: true
                text: "Format for"
            }

            CpChoice {
                value: wipe.fs
                options: page.filesystems
                onPicked: value => wipe.fs = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            FieldBox {
                id: label
                Layout.preferredWidth: 200
                placeholder: "Name (optional)"
            }

            UiText {
                Layout.fillWidth: true
                text: wipe.warning
                color: Theme.danger
                font.pixelSize: Theme.hintSize
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
            }

            PillButton {
                text: "Cancel"
                onClicked: page.form = ""
            }

            PillButton {
                danger: true
                text: page.confirming ? "Yes, " + wipe.action.toLowerCase() : wipe.action
                enabled: !Drives.busy
                onClicked: {
                    if (!page.confirming) {
                        page.confirming = true;
                        return;
                    }
                    wipe.confirmed(wipe.fs, label.text.trim().replace(/[^A-Za-z0-9 _-]/g, "").slice(0, 11));
                    page.form = "";
                    page.confirming = false;
                }
            }
        }
    }
}
