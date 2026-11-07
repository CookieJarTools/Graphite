// Control Panel: Privacy & security. The security sweep (Security.qml: what it found, when, how
// often, and the fixes), the firewall, locking, and whether the disk is encrypted.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    property string opened: "" // the finding whose details show

    readonly property var glyphs: ({ ok: "object-select-symbolic", look: "dialog-warning-symbolic", act: "dialog-error-symbolic", note: "dialog-information-symbolic" })

    spacing: 0

    CpSection {
        title: "Security sweep"

        CpRow {
            glyph: Security.toAct ? "security-low-symbolic" : Security.toLook ? "security-medium-symbolic" : "security-high-symbolic"
            label: Security.running ? "Checking..."
                : !Security.results ? "Not checked yet"
                : Security.toAct ? Security.toAct + (Security.toAct === 1 ? " thing needs doing" : " things need doing")
                : Security.toLook ? Security.toLook + (Security.toLook === 1 ? " thing to look at" : " things to look at")
                : "No problems found"
            hint: Security.results ? "Last checked " + (Search.timeAgo(Security.results.time * 1000) === "now" ? "just now" : Search.timeAgo(Security.results.time * 1000) + (/^\d/.test(Search.timeAgo(Security.results.time * 1000)) ? " ago" : ""))
                : "Looks for security holes, open doors to the network, sign-in attempts, what starts by itself and more"

            PillButton {
                text: Security.running ? "Checking..." : "Check now"
                enabled: !Security.running
                onClicked: Security.sweep()
            }
        }

        CpRow {
            label: "Check automatically"
            hint: "You get a notification when something needs a look"

            CpChoice {
                value: Security.every
                options: [{ value: "day", label: "Every day" }, { value: "week", label: "Every week" }, { value: "off", label: "Never" }]
                onPicked: value => Security.set("every", value)
            }
        }

        CpRow {
            label: "Scan downloads and apps for malware"
            hint: "Downloads, the desktop and apps installed from websites, with ClamAV (its list of malware is about 300 MB)"

            ToggleSwitch {
                on: Security.malware
                onToggled: Security.set("malware", !Security.malware)
            }
        }

        // What it found: the ones to act on first.
        Repeater {
            model: Security.checks.slice().sort((first, second) => ["act", "look", "note", "ok"].indexOf(first.state) - ["act", "look", "note", "ok"].indexOf(second.state))

            CpRow {
                id: finding
                required property var modelData
                glyph: page.glyphs[modelData.state] || "dialog-information-symbolic"
                label: modelData.title
                hint: modelData.summary

                PillButton {
                    visible: finding.modelData.details.length > 0
                    text: page.opened === finding.modelData.id ? "Hide" : "Details"
                    onClicked: page.opened = page.opened === finding.modelData.id ? "" : finding.modelData.id
                }

                // While its fix is under way: installing, then looking again.
                PillButton {
                    readonly property bool installing: !!finding.modelData.fix && Desktop.installingPackages[finding.modelData.fix.package] === true
                    readonly property bool checking: Security.fixing === finding.modelData.id
                    visible: !!finding.modelData.fix
                    primary: finding.modelData.state === "act"
                    enabled: !installing && !checking
                    text: installing ? "Installing..." : checking ? "Checking..." : finding.modelData.fix ? finding.modelData.fix.label : ""
                    onClicked: Security.fix(finding.modelData)
                }

                below: [
                    UiText {
                        Layout.fillWidth: true
                        visible: page.opened === finding.modelData.id
                        text: finding.modelData.details.join("\n")
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                        wrapMode: Text.WordWrap
                        elide: Text.ElideNone
                    }
                ]
            }
        }
    }

    CpSection {
        title: "Protection"
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
