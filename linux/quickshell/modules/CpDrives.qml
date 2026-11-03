// Control Panel: Drives. Every drive and USB stick, its parts and how full they are: open,
// connect or disconnect them, eject a USB stick, format a part or erase a whole drive. The
// drive Graphite runs from is shown but can't be formatted or erased. A Windows dynamic
// disk offers to be opened, then shows its volumes like partitions, or to become a basic disk.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    property bool shown: false
    property string form: ""      // the part (format) or drive (erase) whose form is open
    property bool confirming: false
    // What's chosen and typed in the open form, kept here: the rows are rebuilt when a drive
    // changes (one connecting, filling up), and the form with them.
    property string formFs: "exfat"
    property string formLabel: ""
    onFormChanged: {
        formFs = "exfat";
        formLabel = "";
    }

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
                label: diskSection.modelData.dynamic ? "Windows dynamic disk"
                    : diskSection.modelData.parts.length === 0 ? "Empty drive" : diskSection.modelData.parts.length === 1 ? "1 partition" : diskSection.modelData.parts.length + " partitions"
                hint: diskSection.modelData.path

                PillButton {
                    visible: diskSection.modelData.removable && !diskSection.modelData.system
                    text: "Eject"
                    enabled: !Drives.busy
                    onClicked: Drives.eject(diskSection.modelData)
                }

                PillButton {
                    // An opened dynamic disk is in use by its volumes.
                    visible: !diskSection.modelData.system && page.form !== diskSection.modelData.path
                        && !(diskSection.modelData.dynamic && diskSection.modelData.parts.length > 0)
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

            // A dynamic disk not opened yet: what it is, and both ways to its files.
            CpRow {
                visible: diskSection.modelData.dynamic && diskSection.modelData.parts.length === 0
                glyph: "dialog-information-symbolic"
                label: "Windows keeps this drive in its own layout, which Linux doesn't open by itself"
                hint: "Open it to read and use its files here as it is, or convert it below to use it like any other drive."

                PillButton {
                    text: "Open"
                    enabled: !Drives.busy
                    onClicked: Drives.openDynamic()
                }
            }

            // Or made a basic disk for good, its files kept (graphite-admin dynamic-to-basic).
            CpRow {
                visible: diskSection.modelData.dynamic
                glyph: "drive-harddisk-symbolic"
                label: "Convert to a basic disk"
                hint: "Keeps every file: only the drive's partition table changes, and a copy of the old one is kept. Afterwards Linux and Windows both use it like any other drive. Works when the drive holds one Windows volume."

                PillButton {
                    visible: page.form !== "convert:" + diskSection.modelData.path
                    text: "Convert"
                    enabled: !Drives.busy
                    onClicked: {
                        page.confirming = false;
                        page.form = "convert:" + diskSection.modelData.path;
                    }
                }

                below: [
                    RowLayout {
                        Layout.fillWidth: true
                        visible: page.form === "convert:" + diskSection.modelData.path
                        spacing: Theme.space2

                        UiText {
                            Layout.fillWidth: true
                            text: "Close any app using this drive first. If anything looks wrong, the drive is put back as it was."
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }

                        PillButton {
                            text: "Cancel"
                            onClicked: page.form = ""
                        }

                        PillButton {
                            primary: true
                            text: page.confirming ? "Yes, convert" : "Convert"
                            enabled: !Drives.busy
                            onClicked: {
                                if (!page.confirming) {
                                    page.confirming = true;
                                    return;
                                }
                                Drives.convertDynamic(diskSection.modelData);
                                page.form = "";
                                page.confirming = false;
                            }
                        }
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
                        visible: !diskSection.modelData.system && !partRow.modelData.volume && page.form !== partRow.modelData.path
                        text: "Format"
                        onClicked: {
                            page.confirming = false;
                            page.form = partRow.modelData.path;
                        }
                    }

                    below: [
                        // Windows left it marked in use: why it won't connect, and the ways on.
                        RowLayout {
                            Layout.fillWidth: true
                            visible: Drives.inUse[partRow.modelData.path] === true && !partRow.modelData.mount
                            spacing: Theme.space2

                            UiText {
                                Layout.fillWidth: true
                                text: "Windows left this drive marked as in use, so it can only be read. It happens when Windows' Fast Startup is on or it didn't shut down fully. If you still use Windows, turn off Fast Startup there (Power Options) and shut it down. Repair here only if Windows is shut down fully or you no longer use it."
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                                wrapMode: Text.WordWrap
                                elide: Text.ElideNone
                            }

                            PillButton {
                                text: "Open read-only"
                                enabled: !Drives.busy
                                onClicked: Drives.mountReadOnly(partRow.modelData.path)
                            }

                            PillButton {
                                primary: true
                                text: "Repair"
                                enabled: !Drives.busy
                                onClicked: Drives.repair(partRow.modelData.path)
                            }
                        },

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
        readonly property string fs: page.formFs
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
                onPicked: value => page.formFs = value
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            FieldBox {
                id: label
                Component.onCompleted: text = page.formLabel
                onTextChanged: page.formLabel = text
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
