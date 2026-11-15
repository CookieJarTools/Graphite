// Control Panel: Storage. The clean-up (what it would free now, the wizard that goes through it,
// CpCleanup.qml, and a reminder once a week), the drives, and what fills each one: its biggest
// folders, which open in the file manager (services/Storage.qml looks).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    property string drive: "/"      // the drive whose folders show
    readonly property var shownDrive: Storage.drives.find(item => item.mount === drive) || Storage.drives[0] || null
    readonly property double biggest: shownDrive && shownDrive.top && shownDrive.top.length ? Math.max(...shownDrive.top.map(item => item.size)) : 1

    spacing: 0

    Component.onCompleted: Storage.scanIfOld()

    function ago(seconds) {
        const said = Search.timeAgo(seconds * 1000);
        return said === "now" ? "just now" : said + (/^\d/.test(said) ? " ago" : "");
    }

    CpSection {
        title: "Clean-up"

        CpRow {
            glyph: "user-trash-symbolic"
            label: Storage.cleaning ? "Cleaning..."
                : !Storage.results ? "Looking at your drives..."
                : Storage.easy >= 100e6 ? Machine.size(Storage.easy) + " can be freed"
                : "Nothing much to clean"
            hint: Storage.cleaning ? Storage.step
                : !Storage.results ? "This takes a minute the first time"
                : [Storage.more >= 1e9 ? Machine.size(Storage.more) + " more to choose from" : "",
                   Storage.shots.length ? Storage.shots.length + " new screenshots and recordings to look through" : "",
                   Storage.bin >= 100e6 ? Machine.size(Storage.bin) + " in the Bin" : "",
                   Storage.results.lastCleaned ? "last cleaned " + page.ago(Storage.results.lastCleaned) : ""].filter(part => part).join(" · ")

            PillButton {
                primary: true
                text: "Start clean-up"
                enabled: !!Storage.results && !Storage.cleaning
                onClicked: ShellState.settingsPage = "storage-clean"
            }
        }

        CpRow {
            label: "Remind me every week"
            hint: "A notification when a clean-up would free a gigabyte or more, or there are screenshots to look through"

            ToggleSwitch {
                on: Storage.remind
                onToggled: Storage.setRemind(!Storage.remind)
            }
        }
    }

    CpSection {
        title: "Drives"

        Repeater {
            model: Storage.drives.length ? Storage.drives : Machine.storage

            CpRow {
                id: diskRow
                required property var modelData
                readonly property double percent: modelData.used / Math.max(1, modelData.size)
                glyph: modelData.mount === "/" ? "drive-harddisk-system-symbolic" : "drive-harddisk-symbolic"
                label: modelData.name || (modelData.mount === "/" ? "This computer" : modelData.mount)
                hint: Machine.size(modelData.free) + " free of " + Machine.size(modelData.size)

                below: [
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Theme.surface300

                        Rectangle {
                            width: parent.width * Math.min(1, diskRow.percent)
                            height: parent.height
                            radius: 3
                            color: diskRow.percent > 0.9 ? Theme.danger : Theme.accent
                        }
                    }
                ]
            }
        }
    }

    CpSection {
        title: "What's taking up space"
        visible: !!page.shownDrive

        CpRow {
            label: page.shownDrive ? page.shownDrive.name : ""
            hint: Storage.scanning ? "Looking again..." : Storage.results ? "Looked " + page.ago(Storage.results.time) + ". Click a folder to open it." : ""

            CpChoice {
                visible: Storage.drives.length > 1
                value: page.shownDrive ? page.shownDrive.mount : "/"
                options: Storage.drives.map(item => ({ value: item.mount, label: item.name }))
                onPicked: value => page.drive = value
            }

            PillButton {
                text: Storage.scanning ? "Looking..." : "Look again"
                enabled: !Storage.scanning && !Storage.cleaning
                onClicked: Storage.scan(false)
            }
        }

        CpRow {
            visible: !!page.shownDrive && page.shownDrive.measured === false
            glyph: "dialog-information-symbolic"
            label: "This drive took too long to measure"
            hint: "It holds a great many files. Its folders show in the file manager."
        }

        Repeater {
            model: page.shownDrive ? page.shownDrive.top || [] : []

            CpRow {
                id: folderRow
                required property var modelData
                label: modelData.name
                hint: modelData.where
                opens: modelData.path.length > 0
                onClicked: Quickshell.execDetached(["xdg-open", modelData.path])

                UiText {
                    text: Machine.size(folderRow.modelData.size)
                    color: Theme.inkMuted
                    font.pixelSize: Theme.actionSize
                }

                below: [
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: Theme.surface300

                        Rectangle {
                            width: Math.max(2, parent.width * folderRow.modelData.size / page.biggest)
                            height: parent.height
                            radius: 2
                            color: Theme.accent
                            opacity: 0.8
                        }
                    }
                ]
            }
        }
    }
}
