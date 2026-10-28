// Control Panel: Apps. Installed apps and getting more (the Apps window), the default web
// browser, apps that start when you sign in, and games.
import QtQuick
import QtQuick.Layouts
import Quickshell
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
            hint: "Everything installed, to open or uninstall"
            opens: true
            onClicked: {
                ShellState.settingsOpen = false;
                Desktop.openApps();
            }
        }

        CpRow {
            glyph: "system-software-install-symbolic"
            label: "Get apps"
            hint: "Thousands of apps from Flathub, one click each. Downloaded .deb, AppImage and Flatpak files install themselves when opened."
            opens: true
            onClicked: {
                ShellState.settingsOpen = false;
                Desktop.openAppStore();
            }
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

    CpSection {
        title: "Startup"

        Repeater {
            model: Machine.startup

            CpRow {
                required property string modelData
                readonly property var entry: DesktopEntries.byId(modelData)
                label: entry ? entry.name : modelData
                hint: "Starts when you sign in"

                PillButton {
                    text: "Remove"
                    onClicked: Machine.removeStartup(parent.parent.parent.parent.modelData)
                }
            }
        }

        CpRow {
            label: Machine.startup.length ? "Add another app" : "Start an app when you sign in"
            opens: !page.adding
            onClicked: page.adding = true

            below: [
                Flow {
                    Layout.fillWidth: true
                    visible: page.adding
                    spacing: Theme.space1

                    Repeater {
                        model: page.adding ? page.apps.filter(entry => !Machine.startup.includes(entry.id)) : []

                        PillButton {
                            required property var modelData
                            text: modelData.name
                            onClicked: {
                                Machine.addStartup(modelData.id);
                                page.adding = false;
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
            hint: "Graphics drivers for this computer, Steam, Minecraft (the Modrinth App), GameMode and an FPS overlay"

            PillButton {
                text: "Set up"
                onClicked: Desktop.setUpGaming()
            }
        }
    }
}
