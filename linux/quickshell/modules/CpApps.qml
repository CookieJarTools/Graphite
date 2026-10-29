// Control Panel: Apps. Installed apps and getting more (its own pages: CpAppsList.qml), the
// default web browser, apps that start when you sign in, and games.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

ColumnLayout {
    id: page

    readonly property var apps: Array.from(DesktopEntries.applications.values).filter(entry => !entry.noDisplay).sort((first, second) => first.name.localeCompare(second.name))
    readonly property var browsers: apps.filter(entry => (entry.categories || []).includes("WebBrowser"))
    property bool adding: false

    spacing: 0

    CpSection {
        CpRow {
            glyph: "view-app-grid-symbolic"
            label: "Installed apps"
            hint: "Open or uninstall your apps"
            opens: true
            onClicked: ShellState.settingsPage = "apps-installed"
        }

        CpRow {
            glyph: "system-software-install-symbolic"
            label: "Get apps"
            hint: "Install apps from Arch Linux and Flathub"
            opens: true
            onClicked: ShellState.settingsPage = "apps-get"
        }
    }

    CpSection {
        title: "Default apps"

        CpRow {
            label: "Web browser"
            hint: "Opens links from other apps"

            CpChoice {
                value: Machine.about.browser || ""
                options: page.browsers.map(entry => ({ value: entry.id + ".desktop", label: entry.name }))
                onPicked: value => Machine.setBrowser(value)
            }
        }
    }

    // As Windows' Startup page: each app with a switch, and a search to add one.
    CpSection {
        title: "Startup"

        Repeater {
            model: Machine.startup.concat(Machine.startupOff)
                .map(id => ({ id: id, entry: DesktopEntries.byId(id), on: Machine.startup.includes(id) }))
                .sort((first, second) => (first.entry ? first.entry.name : first.id).localeCompare(second.entry ? second.entry.name : second.id))

            CpRow {
                id: startupRow
                required property var modelData
                icon: modelData.entry ? modelData.entry.icon || modelData.id : modelData.id
                label: modelData.entry ? modelData.entry.name : modelData.id
                hint: modelData.on ? "Opens when you sign in" : "Off"

                ToggleSwitch {
                    on: startupRow.modelData.on
                    onToggled: Machine.setStartupOn(startupRow.modelData.id, !startupRow.modelData.on)
                }

                BarButton {
                    glyph: "user-trash-symbolic"
                    onClicked: Machine.removeStartup(startupRow.modelData.id)
                }
            }
        }

        CpRow {
            glyph: "list-add-symbolic"
            label: Machine.startup.length + Machine.startupOff.length ? "Add another app" : "Start an app when you sign in"
            hint: page.adding ? "" : "Pick an app to open each time you sign in"
            opens: !page.adding
            onClicked: {
                page.adding = true;
                startupSearch.text = "";
            }

            PillButton {
                visible: page.adding
                text: "Done"
                onClicked: page.adding = false
            }

            below: [
                FieldBox {
                    id: startupSearch
                    Layout.fillWidth: true
                    visible: page.adding
                    placeholder: "Search apps"
                },

                // The eight that match best: used most this month first, then by name.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: page.adding
                    spacing: 2

                    Repeater {
                        model: page.adding ? page.apps
                            .filter(entry => !Machine.startup.includes(entry.id) && !Machine.startupOff.includes(entry.id))
                            .filter(entry => !startupSearch.text.trim() || entry.name.toLowerCase().includes(startupSearch.text.trim().toLowerCase()))
                            .sort((first, second) => Apps.usesThisMonth(second.id) - Apps.usesThisMonth(first.id) || first.name.localeCompare(second.name))
                            .slice(0, 8) : []

                        Rectangle {
                            id: pick
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Theme.radiusSm
                            color: pickHover.hovered ? Theme.surface300 : "transparent"

                            HoverHandler { id: pickHover }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space2
                                anchors.rightMargin: Theme.space2
                                spacing: Theme.space3

                                IconImage {
                                    implicitSize: 24
                                    source: Quickshell.iconPath(pick.modelData.icon || pick.modelData.id, "application-x-executable")
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    text: pick.modelData.name
                                }

                                PillButton {
                                    text: "Add"
                                    onClicked: Machine.addStartup(pick.modelData.id)
                                }
                            }
                        }
                    }
                }
            ]
        }
    }

    CpSection {
        title: "Games"

        CpRow {
            glyph: "applications-games-symbolic"
            label: "Set up gaming"
            hint: "Installs graphics drivers, Steam, the Modrinth App for Minecraft, GameMode and an FPS counter"

            PillButton {
                text: "Set up"
                onClicked: Desktop.setUpGaming()
            }
        }
    }
}
