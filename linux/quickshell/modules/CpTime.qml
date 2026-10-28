// Control Panel: Time & language. The clock set by the internet, the time zone (searchable),
// and the computer's name.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    property bool picking: false
    readonly property var matches: {
        const query = zoneSearch.text.trim().toLowerCase().replace(/ /g, "_");
        return Machine.zones.filter(zone => !query || zone.toLowerCase().includes(query)).slice(0, 40);
    }

    spacing: 0

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    CpSection {
        CpRow {
            glyph: "preferences-system-time-symbolic"
            label: Qt.formatDateTime(clock.date, "HH:mm:ss, dddd d MMMM yyyy")
            hint: "The time now, in " + (Machine.about.timezone || "your time zone").replace(/_/g, " ")
        }

        CpRow {
            label: "Set the time automatically"
            hint: "From the internet; always right"
            ToggleSwitch {
                on: Machine.about.ntp === "yes"
                onToggled: Machine.setAutomaticTime(Machine.about.ntp !== "yes")
            }
        }

        CpRow {
            label: "Time zone"
            hint: (Machine.about.timezone || "").replace(/_/g, " ")
            opens: !page.picking
            onClicked: {
                Machine.loadZones();
                page.picking = true;
                zoneSearch.focusField();
            }

            below: [
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.picking
                    spacing: Theme.space1

                    FieldBox {
                        id: zoneSearch
                        Layout.fillWidth: true
                        placeholder: "Search for a city (London, New York, Tokyo...)"
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.space1

                        Repeater {
                            model: page.picking ? page.matches : []

                            PillButton {
                                required property string modelData
                                text: modelData.replace(/_/g, " ")
                                onClicked: {
                                    Machine.setTimeZone(modelData);
                                    page.picking = false;
                                    zoneSearch.text = "";
                                }
                            }
                        }
                    }
                }
            ]
        }
    }

    CpSection {
        title: "This computer"

        CpRow {
            label: "Computer name"
            hint: "How it shows on your network: " + (Machine.about.host || "")

            FieldBox {
                id: hostField
                Layout.preferredWidth: 200
                placeholder: Machine.about.host || ""
                onAccepted: {
                    Machine.setHostname(text);
                    text = "";
                }
            }
        }
    }
}
