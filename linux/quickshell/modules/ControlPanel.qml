// The Control Panel: every setting in one window, as on Windows. A sidebar with who is signed
// in, "Find a setting" (Ctrl+F; it filters the pages by what they hold, Enter opens the first)
// and the pages; the chosen page fills the rest under its title. Opened from the launcher's
// gear, quick settings, the bar's menu, or `qs -c graphite ipc call settings open [page]`;
// Escape closes it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

FloatingWindow {
    id: root

    visible: ShellState.settingsOpen
    title: "Control Panel"
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(720, 480)
    color: Theme.surface100

    onVisibleChanged: {
        if (!visible) {
            ShellState.settingsOpen = false;
            return;
        }
        Machine.refresh();
        search.text = "";
        keys.forceActiveFocus();
    }

    readonly property var pages: [
        { id: "network", name: "Network & internet", glyph: "network-wireless-symbolic", words: "wifi wi-fi wireless internet ethernet cable vpn proxy aeroplane airplane hidden", source: "CpNetwork.qml" },
        { id: "devices", name: "Bluetooth & devices", glyph: "bluetooth-active-symbolic", words: "bluetooth pair headphones mouse touchpad keyboard layout printer scanner speed scroll", source: "CpDevices.qml" },
        { id: "display", name: "Display", glyph: "video-display-symbolic", words: "screen monitor resolution refresh rate hz scale size rotation hdr night light brightness", source: "CpDisplay.qml" },
        { id: "sound", name: "Sound", glyph: "audio-volume-high-symbolic", words: "volume speakers headphones microphone output input apps mute", source: "CpSound.qml" },
        { id: "power", name: "Power & battery", glyph: "battery-good-symbolic", words: "battery power mode performance sleep lock screen off idle", source: "CpPower.qml" },
        { id: "personalise", name: "Personalisation", glyph: "preferences-desktop-appearance-symbolic", words: "dark light theme colours text font taskbar auto-hide home windows tiling zones snap", source: "CpPersonalise.qml" },
        { id: "apps", name: "Apps", glyph: "view-app-grid-symbolic", words: "apps install uninstall store flathub default browser startup games steam", source: "CpApps.qml" },
        { id: "accounts", name: "Accounts", glyph: "avatar-default-symbolic", words: "account name password hint people users add remove administrator", source: "CpAccounts.qml" },
        { id: "time", name: "Time & language", glyph: "preferences-system-time-symbolic", words: "time date clock time zone region computer name hostname", source: "CpTime.qml" },
        { id: "updates", name: "Updates", glyph: "software-update-available-symbolic", words: "update upgrade install automatic restart news", source: "CpUpdates.qml" },
        { id: "security", name: "Privacy & security", glyph: "security-high-symbolic", words: "firewall security privacy lock encryption permissions camera microphone location", source: "CpSecurity.qml" },
        { id: "system", name: "System", glyph: "computer-symbolic", words: "about storage disk space clean processor memory graphics version reload", source: "CpSystem.qml" }
    ]

    readonly property var shownPages: {
        const query = search.text.trim().toLowerCase();
        if (!query) return pages;
        return pages.filter(page => (page.name + " " + page.words).toLowerCase().includes(query));
    }
    readonly property var current: pages.find(page => page.id === ShellState.settingsPage) || pages[0]
    readonly property var me: Machine.people.find(person => person.me) || null

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.settingsOpen = false
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                search.focusField();
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- the sidebar ----------

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 260
                color: Theme.header

                // A warm glow from the lower left, as on the backdrop.
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.55; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.07) }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.line
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space3
                    spacing: Theme.space2

                    // Who is signed in.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space2
                        spacing: Theme.space3

                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: Theme.surface300
                            border.color: Theme.line

                            UiText {
                                anchors.centerIn: parent
                                text: root.me ? (root.me.full || root.me.name).slice(0, 1).toUpperCase() : ""
                                color: Theme.inkMuted
                                font.weight: Font.DemiBold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            UiText {
                                Layout.fillWidth: true
                                text: root.me ? (root.me.full || root.me.name) : ""
                                font.weight: Font.DemiBold
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: root.me && root.me.admin ? "Administrator · Local account" : "Local account"
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                            }
                        }
                    }

                    // Find a setting.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 36
                        radius: Theme.radiusSm
                        color: Theme.surface200
                        border.color: search.activeFocus ? Theme.accent : Theme.line
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space3
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space2

                            Glyph { name: "system-search-symbolic" }

                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                color: Theme.ink
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.actionSize
                                clip: true
                                function focusField() { forceActiveFocus(); selectAll(); }
                                Keys.onReturnPressed: if (root.shownPages.length) ShellState.settingsPage = root.shownPages[0].id
                                Keys.onEscapePressed: {
                                    if (text) text = "";
                                    else ShellState.settingsOpen = false;
                                }

                                UiText {
                                    anchors.fill: parent
                                    visible: search.text.length === 0
                                    text: "Find a setting"
                                    color: Theme.inkMuted
                                    font.pixelSize: Theme.actionSize
                                }
                            }

                            KeyChip { text: "Ctrl" }
                            KeyChip { text: "F" }
                        }
                    }

                    // The pages.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.space2
                        spacing: 2

                        Repeater {
                            model: root.shownPages

                            Rectangle {
                                id: pageButton
                                required property var modelData
                                readonly property bool on: root.current.id === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 38
                                radius: Theme.radiusSm
                                color: on ? Theme.surface300 : pageMouse.containsMouse ? Qt.rgba(Theme.surface300.r, Theme.surface300.g, Theme.surface300.b, 0.5) : "transparent"

                                // The chosen page's mark.
                                Rectangle {
                                    visible: pageButton.on
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 16
                                    radius: 2
                                    color: Theme.accent
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    spacing: Theme.space3

                                    Glyph { name: pageButton.modelData.glyph }

                                    UiText {
                                        Layout.fillWidth: true
                                        text: pageButton.modelData.name
                                        font.weight: pageButton.on ? Font.DemiBold : Font.Normal
                                    }
                                }

                                MouseArea {
                                    id: pageMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: ShellState.settingsPage = pageButton.modelData.id
                                }
                            }
                        }

                        UiText {
                            visible: root.shownPages.length === 0
                            Layout.margins: Theme.space2
                            text: "Nothing matches"
                            color: Theme.inkMuted
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // ---------- the page ----------

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    color: Theme.header

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space6
                        anchors.rightMargin: Theme.space3

                        UiText {
                            Layout.fillWidth: true
                            text: root.current.name
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }

                        BarButton {
                            glyph: "window-close-symbolic"
                            onClicked: ShellState.settingsOpen = false
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.line
                    }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: pageLoader.implicitHeight + Theme.space10
                    boundsBehavior: Flickable.StopAtBounds

                    Loader {
                        id: pageLoader
                        x: Theme.space6
                        width: Math.min(flick.width - Theme.space6 * 2, 820)
                        active: root.visible
                        source: root.current.source
                        onLoaded: {
                            flick.contentY = 0;
                            if (item.shown !== undefined) item.shown = Qt.binding(() => root.visible);
                        }
                    }
                }
            }
        }
    }

    // While Network & internet shows, Wi-Fi scans.
    Binding {
        target: Network
        property: "windowWatching"
        value: root.visible && root.current.id === "network"
        when: root.visible
    }
}
