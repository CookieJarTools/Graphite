// The Control Panel: every setting in one window, as on Windows. A sidebar with who is signed
// in, "Find a setting" (Ctrl+F; it filters the pages by what they hold, Enter opens the first)
// and the pages; the chosen page fills the rest under its title. Opened from the launcher's
// gear, quick settings, the bar's menu, or `qs -c graphite ipc call settings open [page]`.
// It closes only when it's closed.
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
    color: Theme.window

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
        { id: "apps-installed", parent: "apps", kind: "installed", name: "Installed apps", glyph: "view-app-grid-symbolic", words: "installed apps open uninstall remove arch flathub", source: "CpAppsList.qml" },
        { id: "apps-get", parent: "apps", kind: "get", name: "Get apps", glyph: "system-software-install-symbolic", words: "get apps install store flathub download", source: "CpAppsList.qml" },
        { id: "shortcuts", name: "Shortcuts", glyph: "input-keyboard-symbolic", words: "keyboard shortcut keys hotkey change screenshot print", source: "CpShortcuts.qml" },
        { id: "accounts", name: "Accounts", glyph: "avatar-default-symbolic", words: "account name password hint people users add remove administrator", source: "CpAccounts.qml" },
        { id: "time", name: "Time & language", glyph: "preferences-system-time-symbolic", words: "time date clock time zone region computer name hostname", source: "CpTime.qml" },
        { id: "updates", name: "Updates", glyph: "software-update-available-symbolic", words: "update upgrade install automatic restart news", source: "CpUpdates.qml" },
        { id: "security", name: "Privacy & security", glyph: "security-high-symbolic", words: "firewall security privacy lock encryption permissions camera microphone location", source: "CpSecurity.qml" },
        { id: "drives", name: "Drives", glyph: "drive-harddisk-symbolic", words: "drive disk usb stick format erase wipe partition storage eject mount", source: "CpDrives.qml" },
        { id: "storage", name: "Storage", glyph: "drive-harddisk-system-symbolic", words: "storage disk space full free up clean cleanup delete cache caches screenshots recordings downloads bin trash claude chats folders", source: "CpStorage.qml" },
        { id: "storage-clean", parent: "storage", name: "Clean-up", glyph: "edit-clear-all-symbolic", words: "clean up cleanup free space delete caches screenshots recordings downloads bin claude chats", source: "CpCleanup.qml" },
        { id: "system", name: "System", glyph: "computer-symbolic", words: "about processor memory graphics version reload", source: "CpSystem.qml" },
        { id: "troubleshoot", name: "Troubleshoot", glyph: "dialog-information-symbolic", words: "problem fix broken help app won't open not opening slow crash driver nvidia firefox", source: "CpTroubleshoot.qml" }
    ]

    // The line under each page's heading.
    readonly property var blurbs: ({
        "network": "Wi-Fi, cables, VPNs and aeroplane mode.",
        "devices": "Bluetooth, mice, touchpads, keyboards and printers.",
        "display": "Screens, their size and sharpness, and night light.",
        "sound": "Where sound goes and comes from, and how loud.",
        "power": "Battery, power mode, and when the screen sleeps.",
        "personalise": "How the desktop looks and moves, the taskbar and windows.",
        "apps": "What's installed, what opens files, and what starts with you.",
        "apps-installed": "Everything installed, to open or remove.",
        "apps-get": "Find and install more apps.",
        "shortcuts": "The keys that do things, and your own.",
        "accounts": "The people who use this computer, and their passwords.",
        "time": "The clock, the time zone and the computer's name.",
        "updates": "Updates for the system, the apps and Graphite.",
        "security": "The firewall, encryption and what apps may use.",
        "drives": "Drives and USB sticks: connect, eject, format.",
        "storage": "What fills the drives, and room to free up.",
        "storage-clean": "Caches and leftovers that are safe to remove.",
        "system": "This computer, its parts and Graphite's version.",
        "troubleshoot": "Fixes for things that have stopped working."
    })

    // A page's own pages (Apps' Installed apps and Get apps) show in the sidebar only when found.
    readonly property var shownPages: {
        const query = search.text.trim().toLowerCase();
        if (!query) return pages.filter(page => !page.parent);
        return pages.filter(page => (page.name + " " + page.words).toLowerCase().includes(query));
    }
    readonly property var current: pages.find(page => page.id === ShellState.settingsPage) || pages[0]
    readonly property var currentParent: current.parent ? pages.find(page => page.id === current.parent) : null
    readonly property var me: Machine.people.find(person => person.me) || null

    Item {
        id: keys
        anchors.fill: parent
        focus: true
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
                Layout.preferredWidth: Theme.sidebarWidth
                color: Theme.sidebar

                Rectangle {
                    anchors.right: parent.right
                    width: 1
                    height: parent.height
                    color: Theme.divider
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space2 + 2
                    spacing: Theme.space2

                    // Who is signed in.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space1
                        Layout.topMargin: Theme.space2
                        spacing: Theme.space2 + 2

                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: 16
                            color: Theme.accentSoft
                            border.color: Theme.accent
                            border.width: 1

                            UiText {
                                anchors.centerIn: parent
                                text: root.me ? (root.me.full || root.me.name).slice(0, 1).toUpperCase() : ""
                                color: Theme.accentText
                                font.weight: Theme.headingWeight
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            UiText {
                                Layout.fillWidth: true
                                text: root.me ? (root.me.full || root.me.name) : ""
                                font.weight: Theme.headingWeight
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: root.me && root.me.admin ? "Administrator · Local account" : "Local account"
                                color: Theme.inkFaint
                                font.pixelSize: Theme.sectionSize
                            }
                        }
                    }

                    // Find a setting.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 30
                        radius: Theme.radiusControl
                        color: Theme.tileOff
                        border.color: search.activeFocus ? Theme.accentText : Theme.cardBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2 + 2
                            anchors.rightMargin: 5
                            spacing: Theme.space2

                            Glyph {
                                name: "system-search-symbolic"
                                implicitSize: 14
                                tint: Theme.inkFaint
                            }

                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                color: Theme.ink
                                selectionColor: Theme.accentSoft
                                font.family: Theme.fontSans
                                font.pixelSize: Theme.actionSize
                                clip: true
                                Accessible.role: Accessible.EditableText
                                Accessible.name: "Find a setting"
                                function focusField() { forceActiveFocus(); selectAll(); }
                                Keys.onReturnPressed: if (root.shownPages.length) ShellState.settingsPage = root.shownPages[0].id
                                Keys.onEscapePressed: text = ""

                                UiText {
                                    anchors.fill: parent
                                    visible: search.text.length === 0
                                    text: "Find a setting"
                                    color: Theme.inkFaint
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
                        Layout.topMargin: Theme.space1
                        spacing: 1

                        Repeater {
                            model: root.shownPages

                            Rectangle {
                                id: pageButton
                                required property var modelData
                                readonly property bool on: root.current.id === modelData.id || root.current.parent === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 32
                                radius: Theme.radiusRow
                                color: on ? Theme.activeRow : pageMouse.containsMouse ? Theme.hoverRow : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durationInstant; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.ease } }

                                Accessible.role: Accessible.PageTab
                                Accessible.name: modelData.name
                                Accessible.selected: on
                                Accessible.onPressAction: ShellState.settingsPage = modelData.id

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space2 + 2
                                    spacing: Theme.space2 + 2

                                    Glyph {
                                        name: pageButton.modelData.glyph
                                        tint: pageButton.on ? Theme.ink : Theme.inkMuted
                                    }

                                    UiText {
                                        Layout.fillWidth: true
                                        text: pageButton.modelData.name
                                        color: pageButton.on ? Theme.ink : Theme.inkMuted
                                        font.weight: Theme.labelWeight
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
                            color: Theme.inkFaint
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

                // The heading and its line, 28 px down and 36 px in.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 28
                    Layout.leftMargin: root.currentParent ? Theme.space5 : Theme.space9
                    Layout.rightMargin: Theme.space4
                    spacing: Theme.space2

                    // A page's own page: back to it, and its name before this one's.
                    BarButton {
                        Layout.alignment: Qt.AlignTop
                        visible: root.currentParent !== null
                        glyph: "go-previous-symbolic"
                        label: "Back"
                        onClicked: ShellState.settingsPage = root.current.parent
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        UiText {
                            Layout.fillWidth: true
                            text: root.currentParent ? root.currentParent.name + "  ›  " + root.current.name : root.current.name
                            font.pixelSize: Theme.headingSize
                            font.weight: Theme.headingWeight
                            font.letterSpacing: -0.2
                        }

                        UiText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: root.blurbs[root.current.id] || ""
                            color: Theme.inkFaint
                            font.pixelSize: Theme.hintSize
                        }
                    }

                    BarButton {
                        Layout.alignment: Qt.AlignTop
                        visible: !ShellState.deskPlugin
                        glyph: "window-close-symbolic"
                        label: "Close"
                        onClicked: ShellState.settingsOpen = false
                    }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: pageLoader.implicitHeight + Theme.space10
                    boundsBehavior: Flickable.StopAtBounds

                    WheelScroll { flickable: flick }

                    Loader {
                        id: pageLoader
                        x: Theme.space9
                        width: Math.min(flick.width - Theme.space9 * 2, 820)
                        active: root.visible
                        source: root.current.source
                        onLoaded: {
                            flick.contentY = 0;
                            if (item.shown !== undefined) item.shown = Qt.binding(() => root.visible);
                            if (item.kind !== undefined) item.kind = Qt.binding(() => root.current.kind || "");
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
