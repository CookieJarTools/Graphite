// Control Panel: Storage > Clean-up. A wizard in four steps: the caches and leftovers to delete
// (each says what deleting it costs), the screenshots and recordings since the last clean-up
// (click the ones you don't need), old downloads and Claude Code chats, then what it will do and
// how much that frees, with the Bin emptied too if wanted. Files go to the Bin; caches, chats and
// what the Bin held are deleted for good. Storage.clean() does it (system/storage.py clean).
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

ColumnLayout {
    id: page

    property int step: 0
    readonly property var titles: ["Caches and leftovers", "Screenshots and recordings", "Downloads and chats", "Ready to clean"]
    property bool started: false    // the clean-up from this page has begun
    property bool touched: false    // a choice has been changed (a fresh look then keeps them)

    // The choices: true for what goes.
    property var cachesOn: ({})
    property var marked: ({})        // screenshots and recordings, by path
    property var downloadsOn: ({})   // by path
    property int chatAge: 14         // days; 0 keeps them all
    property bool system: true
    property bool emptyBin: false

    readonly property var chosenCaches: Storage.caches.filter(item => cachesOn[item.id] && !item.blocked)
    readonly property double cacheBytes: chosenCaches.reduce((sum, item) => sum + item.size, 0)
    readonly property double systemBytes: system ? Storage.system : 0
    readonly property double chatBytes: chatAge ? Storage.chatsOlderThan(chatAge).size : 0
    readonly property var binned: Storage.shots.filter(item => marked[item.path]).concat(Storage.downloads.filter(item => downloadsOn[item.path]))
    readonly property double binnedBytes: binned.reduce((sum, item) => sum + item.size, 0)
    readonly property double total: cacheBytes + systemBytes + chatBytes + (emptyBin ? Storage.bin + binnedBytes : 0)

    spacing: 0

    Component.onCompleted: choose()

    // The first choices, again once the look's answer has come (the page can open before it
    // has, after a reload), unless one has been changed.
    Connections {
        target: Storage
        function onResultsChanged() {
            if (!page.started && !page.touched) page.choose();
        }
    }

    function choose() {
        const on = {};
        for (const item of Storage.caches) on[item.id] = item.default && !item.blocked;
        cachesOn = on;
        marked = {};
        downloadsOn = {};
        chatAge = 14;
        system = Storage.system >= 1e6;
        emptyBin = false;
    }

    function flip(name, key) {
        const copy = Object.assign({}, page[name]);
        copy[key] = !copy[key];
        page[name] = copy;
        touched = true;
    }

    function markAll(on) {
        const copy = {};
        if (on) for (const item of Storage.shots) copy[item.path] = true;
        marked = copy;
        touched = true;
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(part => encodeURIComponent(part)).join("/");
    }

    function daysOld(seconds) {
        const days = Math.floor((Date.now() / 1000 - seconds) / 86400);
        return days < 1 ? "today" : days === 1 ? "a day old" : days + " days old";
    }

    function chatLabel(days) {
        const old = Storage.chatsOlderThan(days);
        const name = { 7: "Older than a week", 14: "Older than 2 weeks", 30: "Older than a month", 90: "Older than 3 months" }[days];
        return name + (old.count ? " (" + old.count + ", " + Machine.size(old.size) + ")" : " (none)");
    }

    function cleanUp() {
        started = true;
        Storage.clean({
            caches: chosenCaches.map(item => item.id),
            files: binned.map(item => item.path),
            chats: chatAge,
            system: system && Storage.system > 0,
            bin: emptyBin,
            reviewed: true
        });
    }

    // ---------- where the wizard is ----------

    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: !page.started
        spacing: Theme.space2

        UiText {
            text: "Step " + (page.step + 1) + " of " + page.titles.length
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space1

            Repeater {
                model: page.titles.length

                Rectangle {
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: index <= page.step ? Theme.accent : Theme.surface300
                }
            }
        }

        UiText {
            Layout.topMargin: Theme.space2
            text: page.titles[page.step]
            font.pixelSize: Theme.nameSize
        }
    }

    // ---------- 1: caches and leftovers ----------

    CpSection {
        visible: !page.started && page.step === 0
        title: "Deleted for good. Apps and games make these again when they need them."

        Repeater {
            model: Storage.caches

            CpRow {
                id: cacheRow
                required property var modelData
                label: modelData.title
                hint: modelData.blocked ? modelData.detail + " " + modelData.blocked + "." : modelData.detail
                enabled: !modelData.blocked

                UiText {
                    text: Machine.size(cacheRow.modelData.size)
                    color: Theme.inkMuted
                    font.pixelSize: Theme.actionSize
                }

                ToggleSwitch {
                    on: !!page.cachesOn[cacheRow.modelData.id] && !cacheRow.modelData.blocked
                    onToggled: page.flip("cachesOn", cacheRow.modelData.id)
                }
            }
        }

        CpRow {
            visible: Storage.system >= 1e6
            label: "Old updates and logs"
            hint: "Arch's earlier package downloads and old system logs. It asks for your password."

            UiText {
                text: Machine.size(Storage.system)
                color: Theme.inkMuted
                font.pixelSize: Theme.actionSize
            }

            ToggleSwitch {
                on: page.system
                onToggled: {
                    page.system = !page.system;
                    page.touched = true;
                }
            }
        }
    }

    // ---------- 2: screenshots and recordings ----------

    CpSection {
        visible: !page.started && page.step === 1
        title: Storage.shots.length ? "Click the ones you don't need: they go to the Bin. Double-click to open one." : ""

        CpRow {
            visible: Storage.shots.length === 0
            glyph: "emblem-ok-symbolic"
            label: "No new screenshots or recordings"
            hint: "None since your last clean-up."
        }

        CpRow {
            visible: Storage.shots.length > 0
            readonly property var gone: Storage.shots.filter(item => page.marked[item.path])
            label: gone.length + " of " + Storage.shots.length + " to the Bin"
            hint: (gone.length ? Machine.size(gone.reduce((sum, item) => sum + item.size, 0)) + " · " : "")
                + "Since " + (Storage.results && Storage.results.lastCleaned ? "your last clean-up" : "a month ago")

            PillButton {
                text: "Keep all"
                onClicked: page.markAll(false)
            }

            PillButton {
                text: "Bin all"
                danger: true
                onClicked: page.markAll(true)
            }
        }

        // Tiles about 186 px wide, as many as fit, stretched to fill the row.
        Flow {
            id: grid
            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (186 + spacing)))
            readonly property real tileWidth: (width - spacing * (columns - 1)) / columns
            Layout.fillWidth: true
            Layout.topMargin: Theme.space2
            spacing: Theme.space2

            Repeater {
                model: Storage.shots

                Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool gone: !!page.marked[modelData.path]
                    width: grid.tileWidth
                    height: picture.height + 38
                    radius: Theme.radiusMd
                    color: Theme.surface200
                    border.color: gone ? Theme.danger : tileMouse.containsMouse ? Theme.lineStrong : Theme.line
                    border.width: gone ? 2 : 1
                    clip: true

                    Image {
                        id: picture
                        x: 4
                        y: 4
                        width: parent.width - 8
                        height: Math.round(width * 9 / 16)
                        source: tile.modelData.thumb ? page.fileUrl(tile.modelData.thumb) : ""
                        sourceSize.width: 360
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: tile.gone ? 0.35 : 1
                    }

                    Rectangle {
                        visible: tile.modelData.video
                        x: 10
                        y: 10
                        width: 26
                        height: 26
                        radius: 13
                        color: Theme.scrim

                        Glyph {
                            anchors.centerIn: parent
                            name: "media-playback-start-symbolic"
                            tint: "#ffffff"
                        }
                    }

                    Rectangle {
                        visible: tile.gone
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: picture.y + (picture.height - height) / 2
                        width: binLabel.implicitWidth + Theme.space3 * 2
                        height: 26
                        radius: 13
                        color: Theme.danger

                        UiText {
                            id: binLabel
                            anchors.centerIn: parent
                            text: "To the Bin"
                            color: Theme.onAccent
                            font.pixelSize: Theme.actionSize
                            font.weight: Font.DemiBold
                        }
                    }

                    UiText {
                        x: Theme.space2
                        y: picture.y + picture.height + 8
                        width: parent.width - Theme.space2 * 2
                        text: Qt.formatDateTime(new Date(tile.modelData.time * 1000), "d MMM, HH:mm") + " · " + Machine.size(tile.modelData.size)
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: page.flip("marked", tile.modelData.path)
                        onDoubleClicked: {
                            page.flip("marked", tile.modelData.path);
                            Quickshell.execDetached(["xdg-open", tile.modelData.path]);
                        }
                    }
                }
            }
        }
    }

    // ---------- 3: downloads and chats ----------

    CpSection {
        visible: !page.started && page.step === 2
        title: "Downloads over a month old or over a gigabyte. The ones you choose go to the Bin."

        CpRow {
            visible: Storage.downloads.length === 0
            glyph: "emblem-ok-symbolic"
            label: "Nothing old or big in Downloads"
        }

        Repeater {
            model: Storage.downloads

            CpRow {
                id: downloadRow
                required property var modelData
                glyph: modelData.folder ? "folder-symbolic" : "text-x-generic-symbolic"
                label: modelData.name
                hint: Machine.size(modelData.size) + " · " + page.daysOld(modelData.time)

                ToggleSwitch {
                    on: !!page.downloadsOn[downloadRow.modelData.path]
                    onToggled: page.flip("downloadsOn", downloadRow.modelData.path)
                }
            }
        }
    }

    CpSection {
        visible: !page.started && page.step === 2
        title: "Claude Code chats"

        CpRow {
            glyph: "user-available-symbolic"
            label: "Delete chats"
            hint: Storage.chats.count + " chats, " + Machine.size(Storage.chats.size) + " in all. A deleted chat can't be picked up again; what it changed in your files stays."

            CpChoice {
                value: page.chatAge
                options: [{ value: 0, label: "Keep them all" }].concat([7, 14, 30, 90].map(days => ({ value: days, label: page.chatLabel(days) })))
                onPicked: value => {
                    page.chatAge = value;
                    page.touched = true;
                }
            }
        }
    }

    // ---------- 4: ready ----------

    CpSection {
        visible: !page.started && page.step === 3
        title: "What happens"

        CpRow {
            visible: page.chosenCaches.length > 0
            glyph: "user-trash-symbolic"
            label: "Delete caches and leftovers"
            hint: page.chosenCaches.map(item => item.title).join(", ") + " · " + Machine.size(page.cacheBytes)
        }

        CpRow {
            visible: page.systemBytes > 0
            glyph: "software-update-available-symbolic"
            label: "Delete old updates and logs"
            hint: Machine.size(page.systemBytes) + " · asks for your password"
        }

        CpRow {
            visible: page.chatBytes > 0
            glyph: "user-available-symbolic"
            label: "Delete " + Storage.chatsOlderThan(page.chatAge).count + " Claude Code chats"
            hint: Machine.size(page.chatBytes)
        }

        CpRow {
            visible: page.binned.length > 0
            glyph: "user-trash-symbolic"
            label: "Put " + page.binned.length + (page.binned.length === 1 ? " file" : " files") + " in the Bin"
            hint: Machine.size(page.binnedBytes) + (page.emptyBin ? "" : ", freed once the Bin is emptied")
        }

        CpRow {
            glyph: "user-trash-full-symbolic"
            label: "Empty the Bin too"
            hint: (Storage.bin > 0 ? Machine.size(Storage.bin) + " in it now" : "It's empty now") + (page.binned.length ? ", and the files above" : "") + ". Deleted for good."

            ToggleSwitch {
                on: page.emptyBin
                onToggled: {
                    page.emptyBin = !page.emptyBin;
                    page.touched = true;
                }
            }
        }

        CpRow {
            visible: page.total < 1e6 && page.binned.length === 0
            glyph: "emblem-ok-symbolic"
            label: "Nothing chosen"
            hint: "Go back to choose what to clean."
        }
    }

    // ---------- cleaning, and done ----------

    CpSection {
        visible: page.started

        CpRow {
            glyph: Storage.cleaning ? "emblem-synchronizing-symbolic" : "emblem-ok-symbolic"
            label: Storage.cleaning ? "Cleaning..." : "Freed " + Machine.size(Math.max(0, Storage.freed))
            hint: Storage.cleaning ? Storage.step : page.emptyBin || page.binned.length === 0 ? "All done." : "The files you chose are in the Bin."

            PillButton {
                visible: !Storage.cleaning
                primary: true
                text: "Done"
                onClicked: ShellState.settingsPage = "storage"
            }
        }
    }

    // ---------- back and next ----------

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Theme.space4
        visible: !page.started
        spacing: Theme.space2

        PillButton {
            text: page.step === 0 ? "Cancel" : "Back"
            onClicked: {
                if (page.step === 0) ShellState.settingsPage = "storage";
                else page.step -= 1;
            }
        }

        Item { Layout.fillWidth: true }

        UiText {
            visible: page.step === 3
            text: "Frees " + Machine.size(page.total)
            color: Theme.inkMuted
            font.pixelSize: Theme.actionSize
        }

        PillButton {
            primary: true
            text: page.step < 3 ? "Next" : "Clean up"
            enabled: page.step < 3 || page.total >= 1e6 || page.binned.length > 0
            onClicked: {
                if (page.step < 3) page.step += 1;
                else page.cleanUp();
            }
        }
    }
}
