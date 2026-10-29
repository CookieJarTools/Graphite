// Control Panel: Troubleshoot. Checks what most often stops apps opening, with a fix next to
// each problem, and lists the apps that didn't open lately in their own words.
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

ColumnLayout {
    id: page

    spacing: 0

    Component.onCompleted: Diagnose.run()

    CpSection {
        CpRow {
            glyph: "dialog-information-symbolic"
            label: Diagnose.running ? "Checking..." : Diagnose.checks.some(check => check.state === "fail") ? "Problems found" : "No problems found"
            hint: "Checks graphics, folders, Flathub apps and more"

            PillButton {
                text: "Check again"
                enabled: !Diagnose.running
                onClicked: Diagnose.run()
            }
        }
    }

    CpSection {
        title: "Checks"
        visible: Diagnose.checks.length > 0

        Repeater {
            model: Diagnose.checks

            CpRow {
                id: checkRow
                required property var modelData
                glyph: modelData.state === "ok" ? "emblem-ok-symbolic" : "dialog-warning-symbolic"
                label: modelData.title
                hint: modelData.detail

                PillButton {
                    visible: checkRow.modelData.state !== "ok" && checkRow.modelData.fix.length > 0
                    primary: true
                    text: Diagnose.fixing === checkRow.modelData.fix ? "Fixing..." : (Diagnose.fixLabels[checkRow.modelData.fix] || "Fix")
                    enabled: Diagnose.fixing === ""
                    onClicked: Diagnose.fix(checkRow.modelData.fix)
                }
            }
        }
    }

    CpSection {
        title: "Apps that didn't open"
        visible: Diagnose.failures.length > 0

        Repeater {
            model: Diagnose.failures

            CpRow {
                required property var modelData
                glyph: "application-x-executable-symbolic"
                label: modelData.app + " · " + Qt.formatDateTime(modelData.time, "d MMM, HH:mm")
                hint: modelData.words
            }
        }
    }
}
