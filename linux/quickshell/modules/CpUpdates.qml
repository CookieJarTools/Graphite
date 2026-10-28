// Control Panel: Updates. Whether the computer is up to date, what's waiting, Arch's news to
// read first, one button to install everything (with its progress), a restart when a new
// kernel needs one, and automatic updates.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    property bool showList: false
    readonly property var system: Updates.system
    readonly property bool failed: Updates.started && system.state === "failed"

    spacing: 0

    Component.onCompleted: if (Date.now() - Updates.lastChecked > 10 * 60 * 1000) Updates.check()

    CpSection {
        CpRow {
            glyph: Updates.running ? "emblem-synchronizing-symbolic" : Updates.total > 0 ? "software-update-available-symbolic" : "emblem-ok-symbolic"
            label: Updates.running ? "Updating..."
                : page.failed ? "The update didn't finish"
                : Updates.checking ? "Checking for updates..."
                : Updates.total > 0 ? Updates.total + (Updates.total === 1 ? " update is ready" : " updates are ready")
                : "You're up to date"
            hint: Updates.running ? [page.system.state === "running" ? page.system.step : "", Updates.userStep].filter(part => part).join(" · ")
                : page.failed ? page.system.step
                : Updates.lastChecked ? "Last checked " + Qt.formatTime(new Date(Updates.lastChecked), "HH:mm") : ""

            PillButton {
                visible: !Updates.running
                text: "Check now"
                enabled: !Updates.checking
                onClicked: Updates.check()
            }

            PillButton {
                visible: !Updates.running && (Updates.total > 0 || page.failed)
                primary: true
                text: page.failed ? "Try again" : "Install now"
                onClicked: Updates.install()
            }

            below: [
                // Progress while it runs.
                Rectangle {
                    Layout.fillWidth: true
                    visible: Updates.running
                    implicitHeight: 4
                    radius: 2
                    color: Theme.surface300

                    Rectangle {
                        width: parent.width * Math.max(0.03, (page.system.percent || 0) / 100)
                        height: parent.height
                        radius: 2
                        color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 400 } }
                    }
                },
                UiText {
                    Layout.fillWidth: true
                    visible: Updates.userNote.length > 0
                    text: Updates.userNote
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.WordWrap
                }
            ]
        }

        CpRow {
            visible: !!page.system.restart && !Updates.running
            glyph: "system-reboot-symbolic"
            label: "Restart to finish"
            hint: "A new version of the system's core is ready; it's used after a restart"

            PillButton {
                primary: true
                text: "Restart now"
                onClicked: Updates.restart()
            }
        }

        CpRow {
            visible: Updates.partsChanged && !Updates.running
            glyph: "dialog-password-symbolic"
            label: "Finish updating Graphite Desk"
            hint: "Some of Graphite's system parts changed; putting them in place needs your password"

            PillButton {
                primary: true
                text: "Finish"
                onClicked: Updates.finishSystemParts()
            }
        }
    }

    CpSection {
        title: "Read before updating"
        visible: Updates.news.length > 0

        Repeater {
            model: Updates.news

            CpRow {
                required property var modelData
                glyph: "dialog-information-symbolic"
                label: modelData.title
                hint: "Arch Linux news, " + Qt.formatDate(modelData.date, "d MMMM") + ". Some updates need a step by hand; this says which."
                opens: true
                onClicked: Quickshell.execDetached(["xdg-open", modelData.link])
            }
        }
    }

    CpSection {
        title: "What's waiting"
        visible: Updates.total > 0 && !Updates.running

        CpRow {
            label: [
                Updates.packages.length ? Updates.packages.length + " system" : "",
                Updates.appCount ? Updates.appCount + " app" + (Updates.appCount === 1 ? "" : "s") : "",
                Updates.deskCount ? "Graphite Desk" : ""
            ].filter(part => part).join(", ")
            hint: "The system, your apps and Graphite Desk update together"
            opens: Updates.packages.length > 0
            onClicked: page.showList = !page.showList

            below: [
                UiText {
                    Layout.fillWidth: true
                    visible: page.showList
                    text: Updates.packages.join("\n")
                    color: Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                    elide: Text.ElideNone
                }
            ]
        }
    }

    CpSection {
        title: "Options"

        CpRow {
            label: "Install updates automatically"
            hint: "Once a day, in the background; Arch's news is still shown here when an update needs a step by hand"
            ToggleSwitch {
                on: Updates.autoUpdates
                onToggled: Updates.setAutoUpdates(!Updates.autoUpdates)
            }
        }
    }
}
