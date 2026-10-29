// Apps: everything installed, to open or uninstall, and Flathub, to get more with one click.
// "Installed" lists every app with where it came from (Desktop.sourceLabel); Uninstall asks
// once more before it goes, and the desktop's own parts cannot be removed. "Get apps" shows
// popular picks and searches Flathub; Install shows its progress and turns into "Installed".
// Downloaded files (.deb, AppImage, Flatpak) install themselves when opened, as the page says.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

FloatingWindow {
    id: root

    visible: ShellState.appsOpen
    title: "Apps"
    implicitWidth: 760
    implicitHeight: 760
    minimumSize: Qt.size(520, 480)
    color: Theme.surface100

    onVisibleChanged: {
        if (!visible) {
            ShellState.appsOpen = false;
            return;
        }
        Desktop.refresh();
        filter.text = "";
        flathubQuery.text = "";
        Desktop.results = [];
        focusSearch();
    }

    // Typing goes straight into the page's search.
    readonly property string page: ShellState.appsPage
    onPageChanged: focusSearch()

    function focusSearch() {
        if (page === "get") flathubQuery.forceActiveFocus();
        else filter.forceActiveFocus();
    }

    property string confirming: "" // the app whose Uninstall was pressed once

    Timer {
        id: confirmTimeout
        interval: 3000
        onTriggered: root.confirming = ""
    }

    readonly property var installed: Array.from(DesktopEntries.applications.values)
        .filter(entry => !entry.noDisplay)
        .filter(entry => !filter.text.trim() || entry.name.toLowerCase().includes(filter.text.trim().toLowerCase()))
        .sort((first, second) => first.name.localeCompare(second.name))

    // A search on the Get apps page: Flathub's finds that Arch also has (installed from Arch),
    // the rest of Arch's own, and what only Flathub has.
    readonly property bool searching: flathubQuery.text.trim().length > 0
    readonly property var archOffers: Desktop.results.filter(offer => Desktop.archFor[offer.id] !== undefined || offer.id === "com.valvesoftware.Steam")
    readonly property var flathubOffers: Desktop.results.filter(offer => Desktop.archFor[offer.id] === undefined && offer.id !== "com.valvesoftware.Steam")
    readonly property var archPackages: Desktop.packages.filter(item => !archOffers.some(offer => Desktop.archFor[offer.id] === item.name))

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: ShellState.appsOpen = false

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- head: title, pages, close ----------

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                Layout.leftMargin: Theme.space6
                Layout.rightMargin: Theme.space3
                spacing: Theme.space2

                UiText {
                    text: "Apps"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Item { implicitWidth: Theme.space4 }

                Repeater {
                    model: [{ id: "installed", name: "Installed" }, { id: "get", name: "Get apps" }]

                    Rectangle {
                        required property var modelData
                        readonly property bool on: ShellState.appsPage === modelData.id
                        implicitWidth: pageText.implicitWidth + Theme.space4 * 2
                        implicitHeight: 32
                        radius: 16
                        color: on ? Theme.accentSoft : pageMouse.containsMouse ? Theme.surface300 : "transparent"
                        border.color: on ? Theme.accent : Theme.line
                        border.width: 1

                        UiText {
                            id: pageText
                            anchors.centerIn: parent
                            text: parent.modelData.name
                            color: parent.on ? Theme.ink : Theme.inkMuted
                            font.weight: Font.Medium
                        }

                        MouseArea {
                            id: pageMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: ShellState.appsPage = parent.modelData.id
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                BarButton {
                    glyph: "window-close-symbolic"
                    onClicked: ShellState.appsOpen = false
                }
            }

            // ---------- the search for the page ----------

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space6
                Layout.rightMargin: Theme.space6
                Layout.bottomMargin: Theme.space3
                implicitHeight: 40
                radius: Theme.radiusMd
                color: Theme.surface200
                border.color: (ShellState.appsPage === "get" ? flathubQuery : filter).activeFocus ? Theme.accent : Theme.line
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space3
                    spacing: Theme.space2

                    Glyph { name: "system-search-symbolic" }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: filter
                            anchors.fill: parent
                            visible: ShellState.appsPage === "installed"
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            selectionColor: Theme.accentSoft
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.bodySize
                            Keys.onEscapePressed: ShellState.appsOpen = false
                        }

                        // Flathub is searched a moment after typing stops.
                        TextInput {
                            id: flathubQuery
                            anchors.fill: parent
                            visible: ShellState.appsPage === "get"
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.ink
                            selectionColor: Theme.accentSoft
                            font.family: Theme.fontSans
                            font.pixelSize: Theme.bodySize
                            onTextChanged: searchSoon.restart()
                            Keys.onReturnPressed: Desktop.search(text)
                            Keys.onEscapePressed: ShellState.appsOpen = false
                        }

                        Timer {
                            id: searchSoon
                            interval: 500
                            onTriggered: Desktop.search(flathubQuery.text)
                        }

                        UiText {
                            anchors.fill: parent
                            visible: (ShellState.appsPage === "get" ? flathubQuery : filter).text.length === 0
                            text: ShellState.appsPage === "get" ? "Search Flathub, for example Discord or Steam" : "Search installed apps"
                            color: Theme.inkMuted
                        }
                    }
                }
            }

            // ---------- the lists ----------

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: list.implicitHeight + Theme.space6
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: list
                    x: Theme.space6
                    width: parent.width - Theme.space6 * 2
                    spacing: Theme.space1

                    // Installed.
                    Repeater {
                        model: ShellState.appsPage === "installed" ? root.installed : []

                        AppRow {
                            required property var modelData
                            Layout.fillWidth: true
                            icon: Quickshell.iconPath(modelData.icon, "application-x-executable")
                            name: modelData.name
                            detail: Desktop.sourceLabel(modelData.id) + (modelData.genericName ? " · " + modelData.genericName : "")
                            primary: "Open"
                            onPrimaryClicked: {
                                Apps.launch(modelData);
                                ShellState.appsOpen = false;
                            }
                            secondary: !Desktop.canRemove(modelData.id) ? "" : root.confirming === modelData.id ? "Sure?" : "Uninstall"
                            note: Desktop.canRemove(modelData.id) ? "" : "Part of the desktop"
                            // On Flathub and in Arch: Arch's opens faster and updates with the system.
                            other: Desktop.installing[modelData.id.replace(/\.desktop$/, "")] !== undefined ? "Switching..." : Desktop.canSwitch(modelData.id.replace(/\.desktop$/, "")) ? "Use Arch's version" : ""
                            onOtherClicked: if (Desktop.installing[modelData.id.replace(/\.desktop$/, "")] === undefined) Desktop.switchToArch(modelData.id.replace(/\.desktop$/, ""))
                            onSecondaryClicked: {
                                if (root.confirming !== modelData.id) {
                                    root.confirming = modelData.id;
                                    confirmTimeout.restart();
                                    return;
                                }
                                root.confirming = "";
                                Desktop.uninstall(modelData.id);
                            }
                        }
                    }

                    // Get apps: Arch Linux's own first (they use the system's libraries and
                    // driver, so they open faster), then Flathub for what Arch doesn't have.
                    UiText {
                        Layout.topMargin: Theme.space2
                        visible: ShellState.appsPage === "get" && (!root.searching || root.archOffers.length + root.archPackages.length > 0)
                        text: root.searching ? "From Arch Linux" : "Popular"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: ShellState.appsPage === "get" ? (root.searching ? root.archOffers : Desktop.featured) : []

                        OfferRow {}
                    }

                    Repeater {
                        model: ShellState.appsPage === "get" && root.searching ? root.archPackages : []

                        AppRow {
                            required property var modelData
                            readonly property bool busy: Desktop.installingPackages[modelData.name] === true
                            Layout.fillWidth: true
                            icon: Quickshell.iconPath(modelData.name, "package-x-generic")
                            name: modelData.name
                            detail: modelData.detail
                            primary: modelData.installed ? "Installed" : busy ? "Installing..." : "Install"
                            primaryEnabled: !modelData.installed && !busy
                            onPrimaryClicked: Desktop.installPackage(modelData.name)
                        }
                    }

                    UiText {
                        Layout.topMargin: Theme.space4
                        visible: ShellState.appsPage === "get" && root.searching
                        text: Desktop.searching ? "Searching Flathub..." : root.flathubOffers.length ? "From Flathub" : "Nothing more on Flathub"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: ShellState.appsPage === "get" && root.searching ? root.flathubOffers : []

                        OfferRow {}
                    }

                    // Not found in either: the app's own website.
                    AppRow {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.space2
                        visible: ShellState.appsPage === "get" && flathubQuery.text.trim().length > 0
                        icon: Quickshell.iconPath("web-browser", "applications-internet")
                        name: "Search the web for \"" + flathubQuery.text.trim() + "\""
                        detail: "Download it from its website. You'll be asked to install it."
                        primary: "Search"
                        onPrimaryClicked: Desktop.searchWeb(flathubQuery.text)
                    }

                    UiText {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.space4
                        visible: ShellState.appsPage === "get"
                        wrapMode: Text.Wrap
                        text: "Downloaded an app from a website? When the download finishes, you'll be asked to install it. You can also open the file to install it. This works for .deb, AppImage and Flatpak files."
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }
            }
        }
    }

    // An app from the Popular list or a search: from Arch when Arch has it, else from Flathub.
    component OfferRow: AppRow {
        required property var modelData
        readonly property bool busy: Desktop.installing[modelData.id] !== undefined
        readonly property bool done: Desktop.isInstalled(modelData.id)
        Layout.fillWidth: true
        icon: Quickshell.iconPath(modelData.id, true) || Quickshell.iconPath(Desktop.archFor[modelData.id] || "system-software-install", "system-software-install")
        name: modelData.name
        detail: (modelData.detail ? modelData.detail + " · " : "") + "From " + Desktop.originOf(modelData.id)
        primary: done ? "Installed" : busy ? "Installing..." : "Install"
        primaryEnabled: !done && !busy
        onPrimaryClicked: Desktop.install(modelData.id)
    }

    // One app: icon, name, a line about it, and its buttons.
    component AppRow: Rectangle {
        id: row

        property string icon
        property string name
        property string detail
        property string primary
        property bool primaryEnabled: true
        property string secondary
        property string other // a plain button before the others (Switch to Arch's copy)
        property string note
        signal primaryClicked()
        signal secondaryClicked()
        signal otherClicked()

        implicitHeight: 60
        radius: Theme.radiusMd
        color: rowHover.hovered ? Theme.surface200 : "transparent"

        HoverHandler { id: rowHover }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3
            anchors.rightMargin: Theme.space3
            spacing: Theme.space3

            IconImage {
                implicitSize: 36
                source: row.icon
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                UiText {
                    Layout.fillWidth: true
                    text: row.name
                    font.weight: Font.Medium
                }

                UiText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.detail
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            UiText {
                visible: row.note.length > 0
                text: row.note
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            Rectangle {
                visible: row.other.length > 0
                implicitWidth: otherText.implicitWidth + Theme.space4 * 2
                implicitHeight: 32
                radius: Theme.radiusSm
                color: otherMouse.containsMouse ? Theme.surface300 : "transparent"
                border.color: Theme.line
                border.width: 1

                UiText {
                    id: otherText
                    anchors.centerIn: parent
                    text: row.other
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: otherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: row.otherClicked()
                }
            }

            Rectangle {
                visible: row.secondary.length > 0
                implicitWidth: secondaryText.implicitWidth + Theme.space4 * 2
                implicitHeight: 32
                radius: Theme.radiusSm
                color: secondaryMouse.containsMouse ? Zones.alpha(Theme.danger, 0.18) : "transparent"
                border.color: row.secondary === "Sure?" ? Theme.danger : Theme.line
                border.width: 1

                UiText {
                    id: secondaryText
                    anchors.centerIn: parent
                    text: row.secondary
                    color: Theme.danger
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: secondaryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: row.secondaryClicked()
                }
            }

            Rectangle {
                implicitWidth: primaryText.implicitWidth + Theme.space4 * 2
                implicitHeight: 32
                radius: Theme.radiusSm
                color: !row.primaryEnabled ? Theme.surface300 : primaryMouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent
                opacity: row.primaryEnabled ? 1 : 0.8

                UiText {
                    id: primaryText
                    anchors.centerIn: parent
                    text: row.primary
                    color: row.primaryEnabled ? Theme.onAccent : Theme.inkMuted
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: primaryMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: row.primaryEnabled
                    onClicked: row.primaryClicked()
                }
            }
        }
    }
}
