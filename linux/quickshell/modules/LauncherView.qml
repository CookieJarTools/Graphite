// The launcher's content, shared by the launcher (Super), the compact search (Alt+Space,
// mode "palette") and Home (mode "home"). Typing searches apps, files, folders and commands
// (Search.qml): the scope chips appear (Tab moves between them), arrows move, Enter opens,
// Ctrl+Enter opens as administrator, Escape clears the search first. With nothing typed the
// launcher shows Places (Alt+1..9), the Pinned apps and every app, the most used this month
// first; Home and the palette Recent, with nothing picked until an arrow is pressed.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.config
import qs.services

FocusScope {
    id: root

    property string mode: "launcher"
    readonly property bool compact: mode === "palette"
    signal done()   // something was opened, or Escape on an empty search

    property string query: ""
    property string scope: "All"
    property int selected: 0
    property bool altHeld: false
    property string pendingPower: ""
    readonly property string trimmed: query.trim()
    readonly property bool searching: trimmed.length > 0

    readonly property var groups: searching ? Search.groups(trimmed, scope) : []
    readonly property var totals: {
        if (!searching) return {};
        const counts = {};
        for (const group of Search.groups(trimmed, "All")) counts[group.kind] = group.total;
        return counts;
    }
    readonly property int recentCount: mode === "home" ? 6 : 4
    readonly property var idleRows: mode === "launcher" ? Search.appsByUse() : Search.recentRows(recentCount)
    // Every selectable row, in order.
    readonly property var rows: searching ? groups.reduce((list, group) => list.concat(group.items), []) : idleRows

    function reset() {
        input.text = "";
        ShellState.showHints = false;
        scope = "All";
        selected = mode === "launcher" ? 0 : -1;
        pendingPower = "";
        flick.contentY = 0;
        input.forceActiveFocus();
    }

    function focusSearch() {
        input.forceActiveFocus();
    }

    function openRow(item, asAdmin) {
        if (!item) return;
        Search.open(item, asAdmin);
        done();
    }

    function move(delta) {
        if (rows.length === 0) return;
        selected = selected < 0 ? (delta > 0 ? 0 : rows.length - 1) : Math.max(0, Math.min(rows.length - 1, selected + delta));
        const row = rowItems[selected];
        if (!row) return;
        const top = row.mapToItem(body, 0, 0).y;
        if (top < flick.contentY) flick.contentY = top - Theme.space2;
        else if (top + row.height > flick.contentY + flick.height) flick.contentY = top + row.height - flick.height + Theme.space2;
    }

    property var rowItems: ({})

    function cycleScope(delta) {
        const index = Search.scopes.indexOf(scope);
        scope = Search.scopes[(index + delta + Search.scopes.length) % Search.scopes.length];
        selected = 0;
    }

    // Destructive power actions need a second press within three seconds.
    readonly property var powerActions: [
        { name: "Lock", action: "lock", glyph: "system-lock-screen-symbolic", confirm: false },
        { name: "Sign out", action: "signout", glyph: "system-log-out-symbolic", confirm: true },
        { name: "Sleep", action: "sleep", glyph: "system-suspend-symbolic", confirm: false },
        { name: "Restart", action: "restart", glyph: "system-reboot-symbolic", confirm: true },
        { name: "Shut down", action: "shutdown", glyph: "system-shutdown-symbolic", confirm: true }
    ]

    function pressPower(power) {
        if (power.confirm && pendingPower !== power.action) {
            pendingPower = power.action;
            powerTimeout.restart();
            return;
        }
        pendingPower = "";
        done();
        Search.power(power.action);
    }

    Timer {
        id: powerTimeout
        interval: 3000
        onTriggered: root.pendingPower = ""
    }

    // The signed-in person: the first part of their full name, or their user name.
    property string userName: Quickshell.env("USER") || ""
    Process {
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
        stdout: StdioCollector {
            onStreamFinished: { if (this.text.trim()) root.userName = this.text.trim(); }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Alt) root.altHeld = true;
    }
    Keys.onReleased: event => {
        if (event.key === Qt.Key_Alt) root.altHeld = false;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---------- search field ----------

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.compact ? 52 : 60
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space4
            spacing: Theme.space3

            Glyph { name: "system-search-symbolic" }

            TextInput {
                id: input

                Layout.fillWidth: true
                focus: true
                color: Theme.ink
                selectionColor: Theme.accentSoft
                font.family: Theme.fontSans
                font.pixelSize: root.mode === "home" ? 22 : 18
                clip: true
                onTextChanged: {
                    root.query = text;
                    root.selected = text.trim() ? 0 : (root.mode === "launcher" ? 0 : -1);
                    flick.contentY = 0;
                }
                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    if (event.key === Qt.Key_Alt) {
                        root.altHeld = true;
                        return;
                    }
                    if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && !root.compact) {
                        const place = Search.places[event.key - Qt.Key_1];
                        if (place) {
                            Search.openFolder(place.path);
                            root.done();
                        }
                    } else if (event.key === Qt.Key_Down) root.move(1);
                    else if (event.key === Qt.Key_Up) root.move(-1);
                    else if (event.key === Qt.Key_Tab && root.searching) root.cycleScope(1);
                    else if (event.key === Qt.Key_Backtab && root.searching) root.cycleScope(-1);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.searching && root.rows.length === 0) {
                            Search.searchWeb(root.trimmed);
                            root.done();
                        } else {
                            root.openRow(root.rows[Math.max(0, root.selected)], ctrl);
                        }
                    } else if (event.key === Qt.Key_Escape) {
                        if (ShellState.menu) ShellState.menu = null;
                        else if (text.length > 0) text = "";
                        else root.done();
                    } else return;
                    event.accepted = true;
                }
                Keys.onReleased: event => {
                    if (event.key === Qt.Key_Alt) root.altHeld = false;
                }

                UiText {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    text: root.mode === "home" ? "Search apps, files, settings and the web" : root.compact ? "Search" : "Search apps, files and commands"
                    color: Theme.inkMuted
                    font.pixelSize: input.font.pixelSize
                }
            }
        }

        // ---------- scopes, while searching ----------

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space4
            Layout.bottomMargin: Theme.space2
            visible: root.searching
            spacing: Theme.space1

            Repeater {
                model: Search.scopes

                Rectangle {
                    required property var modelData
                    readonly property bool on: root.scope === modelData
                    implicitWidth: chip.implicitWidth + Theme.space3 * 2
                    implicitHeight: 26
                    radius: 13
                    color: on ? Theme.accentSoft : chipMouse.containsMouse ? Theme.surface300 : "transparent"
                    border.color: on ? Theme.accent : Theme.line
                    border.width: 1

                    RowLayout {
                        id: chip
                        anchors.centerIn: parent
                        spacing: Theme.space1

                        UiText {
                            text: parent.parent.modelData
                            font.pixelSize: Theme.hintSize
                            color: parent.parent.on ? Theme.ink : Theme.inkMuted
                        }

                        UiText {
                            visible: parent.parent.modelData !== "All"
                            text: root.totals[parent.parent.modelData] || 0
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.identifierSize
                            color: Theme.inkMuted
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.scope = parent.modelData;
                            root.selected = 0;
                            input.forceActiveFocus();
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.line
            visible: root.mode !== "home"
        }

        // ---------- results ----------

        Flickable {
            id: flick

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: body.implicitHeight + Theme.space2 * 2
            boundsBehavior: Flickable.StopAtBounds

            WheelScroll { flickable: flick }

            ColumnLayout {
                id: body

                x: Theme.space2
                y: Theme.space2
                width: flick.width - Theme.space2 * 2
                spacing: 2

                // Nothing found: Enter searches the web.
                UiText {
                    Layout.fillWidth: true
                    Layout.margins: Theme.space4
                    visible: root.searching && root.rows.length === 0
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.StyledText
                    text: `Nothing matches “${Search.mark(root.trimmed, "")}”. <font color="${Theme.inkMuted}">Enter searches the web.</font>`
                    wrapMode: Text.Wrap
                }

                // Places, launcher only, while idle.
                Section {
                    visible: !root.searching && root.mode === "launcher" && Search.places.length > 0
                    title: "Places"
                    note: ShellState.showHints ? "Alt + number" : ""
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space2
                    visible: !root.searching && root.mode === "launcher" && Search.places.length > 0
                    spacing: Theme.space1

                    Repeater {
                        model: Search.places.slice(0, 9)

                        Rectangle {
                            id: place
                            required property var modelData
                            required property int index
                            implicitWidth: placeRow.implicitWidth + Theme.space3 * 2
                            implicitHeight: 30
                            radius: Theme.radiusSm
                            color: placeMouse.containsMouse ? Theme.surface300 : Theme.surface100
                            border.color: Theme.line
                            border.width: 1

                            RowLayout {
                                id: placeRow
                                anchors.centerIn: parent
                                spacing: Theme.space2

                                Glyph { name: "folder-symbolic" }
                                UiText { text: place.modelData.name }
                                KeyChip {
                                    visible: root.altHeld
                                    text: place.index + 1
                                }
                            }

                            MouseArea {
                                id: placeMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    Search.openFolder(place.modelData.path);
                                    root.done();
                                }
                            }
                        }
                    }
                }

                // Pinned, launcher only, while idle.
                Section {
                    visible: !root.searching && root.mode === "launcher"
                    title: "Pinned"
                    count: Search.pinnedApps().length
                }

                UiText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space2
                    Layout.bottomMargin: Theme.space2
                    visible: !root.searching && root.mode === "launcher" && Search.pinnedApps().length === 0
                    text: "Right-click any app in the results and choose Pin."
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.space2
                    visible: !root.searching && root.mode === "launcher"
                    columns: 6
                    rowSpacing: Theme.space1
                    columnSpacing: Theme.space1

                    Repeater {
                        model: !root.searching && root.mode === "launcher" ? Search.pinnedApps() : []

                        Rectangle {
                            id: tile
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 84
                            radius: Theme.radiusMd
                            color: tileMouse.containsMouse ? Theme.surface300 : "transparent"

                            UiText {
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: Theme.space1
                                text: tile.modelData.alias
                                color: Theme.inkMuted
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.identifierSize
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                width: parent.width - Theme.space2 * 2
                                spacing: Theme.space1

                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 32
                                    source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: tile.modelData.name
                                    font.pixelSize: Theme.hintSize
                                }
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: event => {
                                    if (event.button === Qt.RightButton) root.openMenu(tile, event, tile.modelData);
                                    else root.openRow(tile.modelData, (event.modifiers & Qt.ControlModifier) !== 0);
                                }
                            }
                        }
                    }
                }

                Section {
                    visible: !root.searching && root.idleRows.length > 0
                    title: root.mode === "launcher" ? "Apps, most used this month first" : "Recent"
                }

                // The rows: grouped by kind while searching, the apps (or Recent) while idle.
                Repeater {
                    model: root.searching ? root.groups.filter(group => group.items.length > 0) : [{ kind: "", items: root.idleRows }]

                    ColumnLayout {
                        id: group
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 2

                        // Rows before this group, for each row's place in root.rows.
                        readonly property int offset: {
                            if (!root.searching) return 0;
                            const shown = root.groups.filter(candidate => candidate.items.length > 0);
                            let total = 0;
                            for (let index = 0; index < group.index; index++) total += shown[index].items.length;
                            return total;
                        }

                        Section {
                            visible: root.searching && root.scope === "All"
                            title: group.modelData.kind
                            count: group.modelData.total !== undefined ? group.modelData.total : -1
                        }

                        Repeater {
                            model: group.modelData.items

                            ResultRow {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                item: modelData
                                match: root.trimmed
                                selected: root.selected === group.offset + index
                                Component.onCompleted: root.rowItems[group.offset + index] = this
                                onHovered: root.selected = group.offset + index
                                onActivated: asAdmin => root.openRow(modelData, asAdmin)
                                onMenuRequested: event => { if (modelData.kind === "Apps") root.openMenu(this, event, modelData); }
                            }
                        }
                    }
                }
            }
        }

        // ---------- footer ----------

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.line
            visible: root.mode !== "home"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.leftMargin: Theme.space4
            Layout.rightMargin: Theme.space3
            spacing: Theme.space3

            // Who is signed in (not in the palette).
            Rectangle {
                visible: !root.compact
                implicitWidth: 28
                implicitHeight: 28
                radius: 14
                color: Theme.accent

                UiText {
                    anchors.centerIn: parent
                    text: root.userName.slice(0, 1).toUpperCase()
                    color: Theme.onAccent
                    font.weight: Font.DemiBold
                }
            }

            UiText {
                visible: !root.compact
                text: root.pendingPower ? "Press again to " + root.powerActions.find(power => power.action === root.pendingPower).name.toLowerCase() : root.userName
                color: root.pendingPower ? Theme.accent : Theme.ink
            }

            Item { Layout.fillWidth: true }

            // Key hints: only after a fast wiggle of the mouse (see the HoverHandler below).
            Repeater {
                model: !ShellState.showHints ? [] : root.searching ? [["↑↓", "Move"], ["Enter", "Open"], ["Tab", "Scope"], ["Ctrl+Enter", "As admin"]]
                    : root.mode === "home" ? [["Super", "Search"], ["Super E", "Files"], ["Alt Space", "Quick search"]]
                    : root.compact ? [["Enter", "Open"], ["Esc", "Close"]]
                    : [["Type an alias", "Jump"], ["Alt 1–9", "Places"]]

                RowLayout {
                    required property var modelData
                    spacing: Theme.space1
                    KeyChip { text: parent.modelData[0] }
                    UiText {
                        text: parent.modelData[1]
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }
            }

            // The Control Panel (settings) and the task manager.
            BarButton {
                implicitWidth: 32
                implicitHeight: 32
                glyph: "emblem-system-symbolic"
                onClicked: {
                    root.done();
                    ShellState.openSettings("");
                }
            }

            BarButton {
                visible: !root.compact
                implicitWidth: 32
                implicitHeight: 32
                glyph: "utilities-system-monitor-symbolic"
                onClicked: {
                    root.done();
                    ShellState.openTaskManager();
                }
            }

            Rectangle {
                visible: !root.compact
                implicitWidth: 1
                implicitHeight: 20
                color: Theme.line
            }

            Repeater {
                model: root.compact ? [] : root.powerActions

                BarButton {
                    required property var modelData
                    implicitWidth: 32
                    implicitHeight: 32
                    glyph: modelData.glyph
                    active: root.pendingPower === modelData.action
                    onClicked: root.pressPower(modelData)
                }
            }
        }
    }

    // The key hints stay hidden until the mouse is wiggled fast from side to side for a couple
    // of seconds (a dozen quick turns), then show until the launcher next opens.
    HoverHandler {
        property real lastX: 0
        property int direction: 0
        property var turns: []

        onPointChanged: {
            const x = point.position.x;
            const moved = x - lastX;
            lastX = x;
            if (Math.abs(moved) < 4 || ShellState.showHints) return;
            const now = Date.now();
            const heading = moved > 0 ? 1 : -1;
            if (heading === direction) return;
            direction = heading;
            turns = turns.filter(time => now - time < 2500).concat([now]);
            if (turns.length >= 12) {
                ShellState.showHints = true;
                turns = [];
            }
        }
    }

    // A right-click menu over the launcher, at the pointer.
    function openMenu(target, event, item) {
        const point = target.mapToItem(null, event.x, event.y);
        const window = QsWindow.window;
        ShellState.openMenu(window && window.screen ? window.screen.name : "", point.x, point.y, false, Search.appMenu(item));
    }

    // ---------- pieces ----------

    component Section: RowLayout {
        property string title
        property string note
        property int count: -1
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space2
        Layout.topMargin: Theme.space2
        Layout.bottomMargin: Theme.space1
        spacing: Theme.space2

        UiText {
            text: parent.title
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
            font.weight: Font.DemiBold
        }

        UiText {
            visible: parent.count >= 0
            text: parent.count
            color: Theme.inkMuted
            font.family: Theme.fontMono
            font.pixelSize: Theme.identifierSize
        }

        Item { Layout.fillWidth: true }

        UiText {
            visible: !!parent.note
            text: parent.note
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
        }
    }
}
