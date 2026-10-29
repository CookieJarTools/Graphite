// Control Panel: Apps › Installed apps, and Apps › Get apps (ControlPanel.qml's pages
// "apps-installed" and "apps-get", opened from the Apps page, the launcher's Apps and App store
// commands). Installed lists every app with where it came from (Desktop.sourceLabel), to open
// or uninstall: Uninstall asks once more before it goes, and the desktop's own parts can't be
// removed. Get apps shows popular picks and searches Arch's packages, Flathub and GitHub (where
// a project's link finds that project); Install shows its progress and turns into "Installed".
// A GitHub project says what installing it would put on the computer, and from whom, before it
// does. Downloaded files (.deb, AppImage, Flatpak) install themselves when opened, as the page
// says. Opening an app leaves the Control Panel open.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

ColumnLayout {
    id: root

    // "installed" or "get" (the page's id after "apps-").
    property string kind: "installed"
    property bool shown: false

    spacing: Theme.space1

    onShownChanged: if (shown) start()
    onKindChanged: start()
    Component.onCompleted: start()

    function start() {
        Desktop.refresh();
        filter.text = "";
        flathubQuery.text = "";
        Desktop.results = [];
        (kind === "get" ? flathubQuery : filter).forceActiveFocus();
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

    // A search on Get apps: Flathub's finds that Arch also has (installed from Arch), the rest
    // of Arch's own, and what only Flathub has.
    readonly property bool searching: flathubQuery.text.trim().length > 0
    // A GitHub project's link: only GitHub has anything to say.
    readonly property bool githubLink: Desktop.githubRepo(flathubQuery.text) !== ""
    readonly property var archOffers: Desktop.results.filter(offer => Desktop.archFor[offer.id] !== undefined || offer.id === "com.valvesoftware.Steam")
    readonly property var flathubOffers: Desktop.results.filter(offer => Desktop.archFor[offer.id] === undefined && offer.id !== "com.valvesoftware.Steam")
    readonly property var archPackages: Desktop.packages.filter(item => !archOffers.some(offer => Desktop.archFor[offer.id] === item.name))

    // ---------- the search ----------

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        Layout.bottomMargin: Theme.space2
        implicitHeight: 40
        radius: Theme.radiusMd
        color: Theme.surface200
        border.color: (root.kind === "get" ? flathubQuery : filter).activeFocus ? Theme.accent : Theme.line
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
                    visible: root.kind === "installed"
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    selectionColor: Theme.accentSoft
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.bodySize
                    Keys.onEscapePressed: event => {
                        if (text) text = "";
                        else event.accepted = false;
                    }
                }

                // Flathub is searched a moment after typing stops.
                TextInput {
                    id: flathubQuery
                    anchors.fill: parent
                    visible: root.kind === "get"
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.ink
                    selectionColor: Theme.accentSoft
                    font.family: Theme.fontSans
                    font.pixelSize: Theme.bodySize
                    onTextChanged: searchSoon.restart()
                    Keys.onReturnPressed: Desktop.search(text)
                    Keys.onEscapePressed: event => {
                        if (text) text = "";
                        else event.accepted = false;
                    }
                }

                Timer {
                    id: searchSoon
                    interval: 500
                    onTriggered: Desktop.search(flathubQuery.text)
                }

                UiText {
                    anchors.fill: parent
                    visible: (root.kind === "get" ? flathubQuery : filter).text.length === 0
                    text: root.kind === "get" ? "Search for apps, for example Discord or Steam" : "Search installed apps"
                    color: Theme.inkMuted
                }
            }
        }
    }

    // ---------- Installed ----------

    Repeater {
        model: root.kind === "installed" ? root.installed : []

        AppRow {
            required property var modelData
            Layout.fillWidth: true
            icon: Quickshell.iconPath(modelData.icon, "application-x-executable")
            name: modelData.name
            detail: Desktop.sourceLabel(modelData.id) + (modelData.genericName ? " · " + modelData.genericName : "")
            primary: "Open"
            onPrimaryClicked: Apps.launch(modelData)
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

    // ---------- Get apps ----------

    // Arch Linux's own first (they use the system's libraries and driver, so they open faster),
    // then Flathub for what Arch doesn't have.
    UiText {
        Layout.topMargin: Theme.space2
        visible: root.kind === "get" && (!root.searching || root.archOffers.length + root.archPackages.length > 0)
        text: root.searching ? "From Arch Linux" : "Popular"
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    Repeater {
        model: root.kind === "get" ? (root.searching ? root.archOffers : Desktop.featured) : []

        OfferRow {}
    }

    Repeater {
        model: root.kind === "get" && root.searching ? root.archPackages : []

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
        visible: root.kind === "get" && root.searching && !root.githubLink
        text: Desktop.searching ? "Searching Flathub..." : root.flathubOffers.length ? "From Flathub" : "Nothing more on Flathub"
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    Repeater {
        model: root.kind === "get" && root.searching ? root.flathubOffers : []

        OfferRow {}
    }

    // GitHub: the project a link names, or GitHub's most starred matches for the words.
    UiText {
        Layout.topMargin: Theme.space4
        visible: root.kind === "get" && root.searching && (Desktop.githubSearching || Desktop.githubResults.length > 0 || (Desktop.githubErrors[""] || "") !== "")
        text: Desktop.githubSearching && Desktop.githubResults.length === 0 ? "Searching GitHub..." : (Desktop.githubErrors[""] || "") !== "" ? Desktop.githubErrors[""] : "From GitHub"
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
        font.weight: Font.DemiBold
    }

    Repeater {
        model: root.kind === "get" && root.searching ? Desktop.githubResults : []

        GithubRow {}
    }

    // Not found in either: the app's own website.
    AppRow {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space2
        visible: root.kind === "get" && flathubQuery.text.trim().length > 0 && !root.githubLink
        icon: Quickshell.iconPath("web-browser", "applications-internet")
        name: "Search the web for \"" + flathubQuery.text.trim() + "\""
        detail: "Download it from its website. You'll be asked to install it."
        primary: "Search"
        onPrimaryClicked: Desktop.searchWeb(flathubQuery.text)
    }

    UiText {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: root.kind === "get"
        wrapMode: Text.Wrap
        text: "Downloaded an app from a website? When the download finishes, you'll be asked to install it. You can also open the file to install it. This works for .deb, AppImage and Flatpak files."
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
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

    // A project on GitHub: what it is, then what installing it would do (looked up when Check is
    // pressed, at once for a pasted link), then Install; View opens its page.
    component GithubRow: AppRow {
        required property var modelData
        readonly property string repo: modelData.repo
        readonly property var found: Desktop.githubDetails[repo] || null
        readonly property bool checking: Desktop.githubChecking[repo] === true
        readonly property bool busy: Desktop.githubInstalling[repo] === true
        readonly property bool done: Desktop.githubDone[repo] === true
        readonly property string error: Desktop.githubErrors[repo] || ""
        readonly property var info: found || modelData

        Layout.fillWidth: true
        icon: "https://github.com/" + info.owner + ".png?size=72"
        name: info.name + "  ·  " + info.owner
        detail: [info.description, "★ " + (info.stars >= 1000 ? (info.stars / 1000).toFixed(1) + "k" : info.stars),
            found && found.release ? "Release " + found.release + (found.released ? ", " + Qt.formatDate(new Date(found.released), "d MMM yyyy") : "") : ""]
            .filter(Boolean).join("  ·  ")
        extra: error || (found ? Desktop.githubPlan(found) : "")
        extraIsError: error !== "" || (found !== null && !found.choice)
        primary: done ? "Installed" : busy ? "Installing..." : checking ? "Checking..." : !found ? "Check" : found.choice ? "Install" : "No download"
        primaryEnabled: !done && !busy && !checking && (!found || !!found.choice)
        onPrimaryClicked: found ? Desktop.githubInstall(repo) : Desktop.githubCheck(repo, false)
        other: "View"
        onOtherClicked: Qt.openUrlExternally(info.url)
    }

    // One app: icon, name, a line about it, and its buttons.
    component AppRow: Rectangle {
        id: row

        property string icon
        property string name
        property string detail
        property string extra // a second line: what installing does, or what went wrong
        property bool extraIsError: false
        property string primary
        property bool primaryEnabled: true
        property string secondary
        property string other // a plain button before the others (Switch to Arch's copy)
        property string note
        signal primaryClicked()
        signal secondaryClicked()
        signal otherClicked()

        implicitHeight: row.extra ? 76 : 60
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

                UiText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: row.extra
                    color: row.extraIsError ? Theme.danger : Theme.ink
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
