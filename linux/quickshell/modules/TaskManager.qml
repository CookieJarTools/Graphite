// The task manager (Ctrl+Shift+Esc), as Windows 11's: its pages on a rail on the left.
// Processes: the apps with windows (each opens, by its chevron, to show its processes), the
// background processes and the desktop's own, with the processor, memory and disk each uses,
// shaded by how busy, and the totals over each column; search (Ctrl+F), sort by any column,
// End task (Delete) and a right-click menu (a double click on an app switches to it).
// Performance: the processor, memory, disk, network and graphics card, each a card with its
// graph, the chosen one large beside them. Startup apps: what starts when you sign in, each with
// its switch. Numbers come from Tasks.qml while it is open.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.config
import qs.services

FloatingWindow {
    id: root

    visible: ShellState.taskManagerOpen
    title: "Task Manager"
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(760, 480)
    color: Theme.surface100

    property string tab: "processes"    // "processes", "performance" or "startup"
    property string selected: ""         // the chosen row's key
    property string sortBy: "cpu"        // "name", "cpu", "memory" or "disk"
    property bool descending: true
    property var opened: ({})            // the entries opened to show their processes, by key
    property string resource: "cpu"      // the Performance page's large card
    property var menu: null              // the right-click menu: { task, x, y }

    onVisibleChanged: {
        if (!visible) {
            ShellState.taskManagerOpen = false;
            return;
        }
        search.text = "";
        menu = null;
        Tasks.readStartup();
        keys.forceActiveFocus();
    }

    Binding {
        target: Tasks
        property: "watching"
        value: root.visible
    }

    readonly property var pages: [
        { id: "processes", name: "Processes", glyph: "view-list-bullet-symbolic" },
        { id: "performance", name: "Performance", glyph: "speedometer-symbolic" },
        { id: "startup", name: "Startup apps", glyph: "system-run-symbolic" }
    ]
    readonly property var page: pages.find(candidate => candidate.id === tab) || pages[0]

    // The columns' widths, shared by the headings and the rows.
    readonly property int lead: 28        // the chevron's space
    readonly property int cpuWidth: 84
    readonly property int memoryWidth: 104
    readonly property int diskWidth: 96
    readonly property int netWidth: 96

    // ---------- what the list shows ----------

    readonly property string query: search.text.trim().toLowerCase()

    function matches(item) {
        return !query || item.name.toLowerCase().includes(query) || (item.command || "").toLowerCase().includes(query) || String(item.pid || "") === query;
    }

    function sorted(list) {
        return list.slice().sort((first, second) => {
            let order = sortBy === "name" ? first.name.localeCompare(second.name) : (first[sortBy] || 0) - (second[sortBy] || 0);
            if (descending) order = -order;
            return order || first.name.localeCompare(second.name);
        });
    }

    // Clicking a heading sorts by it; again, the other way round (names A to Z first, numbers most first).
    function sortOn(key) {
        if (sortBy === key) descending = !descending;
        else {
            sortBy = key;
            descending = key !== "name";
        }
    }

    // [{ task, processes, own }]: an entry stays when it or one of its processes matches the
    // search; then only the matching processes show beneath it, opened.
    function shown(list) {
        return sorted(list).map(task => {
            const own = matches(task);
            return { task: task, processes: sorted(task.processes.filter(process => own || matches(process))), own: own };
        }).filter(entry => entry.own || entry.processes.length > 0);
    }

    readonly property var appEntries: shown(Tasks.apps)
    readonly property var backgroundEntries: shown(Tasks.background)
    readonly property var desktopEntries: shown(Tasks.desktop)

    // The list as rows: each group's heading, its entries, and an opened entry's processes.
    readonly property var rows: {
        const list = [];
        const add = (title, entries) => {
            if (!entries.length) return;
            list.push({ group: title + " (" + entries.length + ")", key: "group:" + title });
            for (const entry of entries) {
                const open = isOpen(entry);
                list.push({ task: entry.task, depth: 0, expandable: entry.task.processes.length > 1, open: open, key: entry.task.key });
                if (open) for (const process of entry.processes) list.push({ task: process, depth: 1, expandable: false, open: false, key: process.key });
            }
        };
        add("Apps", appEntries);
        add("Background processes", backgroundEntries);
        add("Desktop processes", desktopEntries);
        return list;
    }

    // A row's figures, each on its shade by how busy: the processor (of the whole of it), memory
    // (of all there is) and disk. Linux doesn't count network use per process: its column has
    // only the total, over it.
    function cells(task) {
        return [
            { width: cpuWidth, shade: heat(task.cpu / 100 * 2.5), text: task.cpu.toFixed(1) + "%" },
            { width: memoryWidth, shade: heat(task.memory / Math.max(1, Tasks.memoryTotal) * 8), text: Tasks.size(task.memory) },
            { width: diskWidth, shade: heat(task.disk / (20 * 1048576)), text: task.disk >= 1024 ? Tasks.speed(task.disk) : "0 MB/s" },
            { width: netWidth, shade: heat(0), text: "–", muted: true }
        ];
    }

    function isOpen(entry) {
        return !!opened[entry.task.key] || (query.length > 0 && !entry.own);
    }

    function toggle(key) {
        const next = Object.assign({}, opened);
        next[key] = !next[key];
        opened = next;
    }

    // The chosen row: an entry, or one process beneath one (then ending it ends that process).
    readonly property var everything: Tasks.apps.concat(Tasks.background, Tasks.desktop)
    function taskFor(key) {
        for (const task of everything) {
            if (task.key === key) return task;
            const process = task.processes.find(candidate => candidate.key === key);
            if (process) return Object.assign({}, process, { pids: [process.pid], windows: [], app: false, desk: task.desk, processes: [] });
        }
        return null;
    }
    readonly property var chosen: selected ? taskFor(selected) : null

    function switchTo(task) {
        if (!task || !task.windows.length) return;
        Taskbar.focusWindow(task.windows[0]);
        ShellState.taskManagerOpen = false;
    }

    function endChosen() {
        if (!Tasks.canEnd(chosen)) return;
        Tasks.end(chosen);
        selected = "";
    }

    function openMenu(task, item, x, y) {
        const point = item.mapToItem(keys, x, y);
        selected = task.key;
        menu = { task: task, x: point.x, y: point.y };
    }

    function menuItems(task) {
        if (!task) return [];
        const pid = task.pids.length ? task.pids[0] : 0;
        return [
            { text: "Switch to", visible: task.windows.length > 0, action: () => root.switchTo(task) },
            { separator: true, visible: task.windows.length > 0 },
            { text: "End task", danger: true, enabled: Tasks.canEnd(task), action: () => Tasks.end(task) },
            { text: "End process tree", danger: true, enabled: Tasks.canEnd(task), action: () => Tasks.endTree(task) },
            { separator: true },
            { text: "Open file location", enabled: pid > 0, action: () => Tasks.openLocation(pid) },
            { text: "Search online", action: () => Tasks.searchOnline(task.name) },
            { separator: true },
            { text: "Copy name", action: () => Tasks.copy(task.name) },
            { text: "Copy PID" + (pid ? "  (" + pid + ")" : ""), enabled: pid > 0, action: () => Tasks.copy(pid) }
        ].filter(item => item.visible !== false);
    }

    // A cell's shade, from pale to the accent, by how busy (0 to 1), as Windows shades its columns.
    function heat(level) {
        const amount = Math.max(0, Math.min(1, level || 0));
        return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.05 + 0.45 * amount);
    }

    function percent(fraction) {
        return Math.round(Math.max(0, fraction) * 100) + "%";
    }

    // ---------- the Performance page's cards ----------

    readonly property var resources: {
        const list = [
            { id: "cpu", name: "CPU", detail: Machine.about.cpu || "", value: percent(Tasks.cpu) + "  " + (Tasks.speedMhz / 1000).toFixed(2) + " GHz", points: Tasks.history.cpu, colour: Theme.accent, caption: "% Utilisation over 60 seconds" },
            { id: "memory", name: "Memory", detail: Tasks.size(Tasks.memoryTotal), value: Tasks.size(Tasks.memoryUsed) + " of " + Tasks.size(Tasks.memoryTotal) + "  (" + percent(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal)) + ")", points: Tasks.history.memory, colour: Theme.tagViolet, caption: "Memory in use" },
            { id: "disk", name: "Disk", detail: "Every drive", value: percent(Tasks.diskBusy) + " active", points: Tasks.history.disk, colour: Theme.tagGreen, caption: "Active time of the busiest drive" },
            { id: "network", name: Tasks.link.kind === "wifi" ? "Wi-Fi" : "Ethernet", detail: Tasks.link.name, value: "↓ " + Tasks.speed(Tasks.netDown) + "  ↑ " + Tasks.speed(Tasks.netUp), points: Tasks.history.net, colour: Theme.tagBlue, caption: Tasks.link.mbits > 0 ? "Use of the link" : "Throughput, up to 100 Mbit/s" }
        ];
        if (Tasks.gpu) list.push({ id: "gpu", name: "GPU", detail: Tasks.gpu.name, value: percent(Tasks.gpu.busy) + "  " + Tasks.gpu.temperature + " °C", points: Tasks.history.gpu, colour: Theme.tagTeal, caption: "% Utilisation over 60 seconds" });
        return list;
    }
    readonly property var current: resources.find(candidate => candidate.id === resource) || resources[0]

    // The large card's figures, as Windows lists them under the graph.
    readonly property var figures: {
        const gpu = Tasks.gpu;
        switch (current.id) {
        case "memory":
            return [
                { label: "In use", value: Tasks.size(Tasks.memoryUsed) },
                { label: "Available", value: Tasks.size(Tasks.memoryTotal - Tasks.memoryUsed) },
                { label: "Total", value: Tasks.size(Tasks.memoryTotal) },
                { label: "In use, of all", value: percent(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal)) }
            ];
        case "disk":
            return [
                { label: "Active time", value: percent(Tasks.diskBusy) },
                { label: "Read speed", value: Tasks.speed(Tasks.diskRead) },
                { label: "Write speed", value: Tasks.speed(Tasks.diskWrite) }
            ];
        case "network":
            return [
                { label: "Receive", value: Tasks.speed(Tasks.netDown) },
                { label: "Send", value: Tasks.speed(Tasks.netUp) },
                { label: "Adapter", value: Tasks.link.name || "None" },
                { label: "Link speed", value: Tasks.link.mbits > 0 ? Tasks.link.mbits + " Mbit/s" : "Not reported" }
            ];
        case "gpu":
            return gpu ? [
                { label: "Utilisation", value: percent(gpu.busy) },
                { label: "Dedicated memory", value: (gpu.memoryUsed / 1024).toFixed(1) + " of " + (gpu.memoryTotal / 1024).toFixed(1) + " GB" },
                { label: "Temperature", value: gpu.temperature + " °C" }
            ] : [];
        default:
            return [
                { label: "Utilisation", value: percent(Tasks.cpu) },
                { label: "Speed", value: (Tasks.speedMhz / 1000).toFixed(2) + " GHz" },
                { label: "Processes", value: String(Tasks.processCount) },
                { label: "Threads", value: String(Tasks.threads) },
                { label: "Up time", value: root.duration(Tasks.uptime) },
                { label: "Logical processors", value: String(Tasks.cores) }
            ];
        }
    }

    // 1:04:09:33 for a day, 4 hours, 9 minutes and 33 seconds, as Windows writes up time.
    function duration(seconds) {
        const total = Math.floor(seconds);
        const two = value => String(value).padStart(2, "0");
        return Math.floor(total / 86400) + ":" + two(Math.floor(total % 86400 / 3600)) + ":" + two(Math.floor(total % 3600 / 60)) + ":" + two(total % 60);
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (root.menu) root.menu = null;
            else ShellState.taskManagerOpen = false;
        }
        Keys.onDeletePressed: root.endChosen()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                root.tab = "processes";
                search.forceActiveFocus();
                event.accepted = true;
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ---------- the rail ----------

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 212
                color: Theme.header

                // A warm glow from the lower left, as on the Control Panel.
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
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space2
                        Layout.bottomMargin: Theme.space3
                        spacing: Theme.space3

                        Glyph {
                            name: "utilities-system-monitor-symbolic"
                            tint: Theme.accent
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: "Task Manager"
                            font.weight: Font.DemiBold
                        }
                    }

                    Repeater {
                        model: root.pages

                        Rectangle {
                            id: pageButton
                            required property var modelData
                            readonly property bool on: root.tab === modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: Theme.radiusSm
                            color: on ? Theme.surface300 : pageMouse.containsMouse ? Qt.rgba(Theme.surface300.r, Theme.surface300.g, Theme.surface300.b, 0.5) : "transparent"

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
                                onClicked: {
                                    root.tab = pageButton.modelData.id;
                                    root.menu = null;
                                    if (root.tab === "startup") Tasks.readStartup();
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // The totals, whichever page is open.
                    UiText {
                        Layout.fillWidth: true
                        Layout.margins: Theme.space2
                        text: "CPU " + root.percent(Tasks.cpu) + "  ·  Memory " + root.percent(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal))
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
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
                        spacing: Theme.space2

                        UiText {
                            text: root.page.name
                            font.pixelSize: Theme.nameSize
                            font.weight: Font.DemiBold
                        }

                        Item { Layout.fillWidth: true }

                        // Search: a name, part of a command line, or a PID.
                        Rectangle {
                            visible: root.tab === "processes"
                            Layout.preferredWidth: 300
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

                                Glyph {
                                    name: "system-search-symbolic"
                                    tint: Theme.inkMuted
                                }

                                TextInput {
                                    id: search
                                    Layout.fillWidth: true
                                    color: Theme.ink
                                    selectionColor: Theme.accentSoft
                                    font.family: Theme.fontSans
                                    font.pixelSize: Theme.actionSize
                                    clip: true
                                    Keys.onEscapePressed: {
                                        if (text) text = "";
                                        else ShellState.taskManagerOpen = false;
                                    }

                                    UiText {
                                        anchors.fill: parent
                                        visible: search.text.length === 0
                                        text: "Search by name or PID"
                                        color: Theme.inkMuted
                                        font.pixelSize: Theme.actionSize
                                    }
                                }

                                KeyChip { text: "Ctrl" }
                                KeyChip { text: "F" }
                            }
                        }

                        PillButton {
                            visible: root.tab === "processes"
                            danger: true
                            text: "End task"
                            enabled: Tasks.canEnd(root.chosen)
                            onClicked: root.endChosen()
                        }

                        BarButton {
                            visible: !ShellState.deskPlugin
                            glyph: "window-close-symbolic"
                            onClicked: ShellState.taskManagerOpen = false
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.line
                    }
                }

                // ---------- processes ----------

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Theme.space3
                    Layout.rightMargin: Theme.space3
                    visible: root.tab === "processes"
                    spacing: 0

                    TaskHeading {

                        manager: root
                        Layout.fillWidth: true
                        Layout.leftMargin: root.lead
                        label: "Name"
                        key: "name"
                        alignRight: false
                    }
                    TaskHeading {
                        manager: root
                        Layout.preferredWidth: root.cpuWidth
                        figure: root.percent(Tasks.cpu)
                        label: "CPU"
                        key: "cpu"
                    }
                    TaskHeading {
                        manager: root
                        Layout.preferredWidth: root.memoryWidth
                        figure: root.percent(Tasks.memoryUsed / Math.max(1, Tasks.memoryTotal))
                        label: "Memory"
                        key: "memory"
                    }
                    TaskHeading {
                        manager: root
                        Layout.preferredWidth: root.diskWidth
                        figure: root.percent(Tasks.diskBusy)
                        label: "Disk"
                        key: "disk"
                    }
                    TaskHeading {
                        manager: root
                        Layout.preferredWidth: root.netWidth
                        figure: Tasks.link.mbits > 0 ? root.percent(Tasks.netBusy) : Tasks.speed(Tasks.netDown + Tasks.netUp)
                        label: "Network"
                        key: ""
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.tab === "processes"
                    implicitHeight: 1
                    color: Theme.line
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tab === "processes"
                    clip: true
                    contentHeight: processList.implicitHeight + Theme.space4
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: processList
                        x: Theme.space3
                        width: parent.width - Theme.space3 * 2
                        spacing: 0

                        Repeater {
                            model: root.rows
                            TaskRow { manager: root }
                        }

                        UiText {
                            visible: root.query.length > 0 && root.appEntries.length + root.backgroundEntries.length + root.desktopEntries.length === 0
                            Layout.margins: Theme.space6
                            text: "Nothing running matches “" + search.text.trim() + "”"
                            color: Theme.inkMuted
                        }
                    }
                }

                // ---------- performance ----------

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: Theme.space4
                    visible: root.tab === "performance"
                    spacing: Theme.space4

                    ColumnLayout {
                        Layout.preferredWidth: 240
                        Layout.fillWidth: false
                        Layout.fillHeight: true
                        spacing: Theme.space2

                        Repeater {
                            model: root.resources

                            Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool on: root.current.id === modelData.id
                                Layout.fillWidth: true
                                implicitHeight: 64
                                radius: Theme.radiusMd
                                color: on ? Theme.surface300 : cardMouse.containsMouse ? Theme.surface200 : "transparent"
                                border.color: on ? Qt.rgba(card.modelData.colour.r, card.modelData.colour.g, card.modelData.colour.b, 0.6) : "transparent"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.space2
                                    spacing: Theme.space3

                                    TaskGraph {
                                        Layout.preferredWidth: 64
                                        Layout.fillHeight: true
                                        points: card.modelData.points
                                        colour: card.modelData.colour
                                        small: true
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        UiText {
                                            Layout.fillWidth: true
                                            text: card.modelData.name
                                            font.weight: Font.DemiBold
                                        }

                                        UiText {
                                            Layout.fillWidth: true
                                            text: card.modelData.value
                                            color: Theme.inkMuted
                                            font.pixelSize: Theme.hintSize
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.resource = card.modelData.id
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Theme.radiusMd
                        color: Theme.surface200
                        border.color: Theme.line
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space6
                            spacing: Theme.space2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space3

                                UiText {
                                    text: root.current.name
                                    font.pixelSize: Theme.displaySize
                                    font.weight: Font.DemiBold
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    text: root.current.detail
                                    color: Theme.inkMuted
                                }
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: root.current.caption
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                            }

                            TaskGraph {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.topMargin: Theme.space1
                                points: root.current.points
                                colour: root.current.colour
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.space3
                                columns: 3
                                columnSpacing: Theme.space6
                                rowSpacing: Theme.space3

                                Repeater {
                                    model: root.figures

                                    ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 0

                                        UiText {
                                            text: parent.modelData.label
                                            color: Theme.inkMuted
                                            font.pixelSize: Theme.hintSize
                                        }

                                        UiText {
                                            Layout.fillWidth: true
                                            text: parent.modelData.value
                                            font.pixelSize: 18
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------- startup apps ----------

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.tab === "startup"
                    clip: true
                    contentHeight: startupList.implicitHeight + Theme.space6
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: startupList
                        x: Theme.space6
                        y: Theme.space4
                        width: parent.width - Theme.space6 * 2
                        spacing: 0

                        UiText {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Theme.space3
                            text: "These open by themselves when you sign in. Add more in the Control Panel's Apps page."
                            color: Theme.inkMuted
                            wrapMode: Text.WordWrap
                            elide: Text.ElideNone
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: Tasks.startup.length > 0
                            spacing: 0

                            UiText {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.space3 + 24 + Theme.space3
                                text: "Name"
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                                font.weight: Font.DemiBold
                            }

                            UiText {
                                Layout.preferredWidth: 140
                                text: "Status"
                                color: Theme.inkMuted
                                font.pixelSize: Theme.hintSize
                                font.weight: Font.DemiBold
                            }

                            Item { implicitWidth: 40 + Theme.space3 }
                        }

                        Repeater {
                            model: Tasks.startup

                            Rectangle {
                                id: startupRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.space1
                                implicitHeight: 48
                                radius: Theme.radiusSm
                                color: startupMouse.containsMouse ? Theme.surface200 : "transparent"

                                MouseArea {
                                    id: startupMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    anchors.rightMargin: Theme.space3
                                    spacing: Theme.space3

                                    IconImage {
                                        implicitSize: 24
                                        source: Quickshell.iconPath(startupRow.modelData.icon, "application-x-executable")
                                    }

                                    UiText {
                                        Layout.fillWidth: true
                                        text: startupRow.modelData.name
                                    }

                                    UiText {
                                        Layout.preferredWidth: 140
                                        text: startupRow.modelData.on ? "Enabled" : "Disabled"
                                        color: startupRow.modelData.on ? Theme.ink : Theme.inkMuted
                                    }

                                    ToggleSwitch {
                                        on: startupRow.modelData.on
                                        onToggled: Tasks.setStartup(startupRow.modelData.id, !startupRow.modelData.on)
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: Tasks.startup.length === 0
                            Layout.fillWidth: true
                            Layout.topMargin: Theme.space6
                            spacing: Theme.space3

                            UiText {
                                text: "Nothing starts when you sign in"
                                font.weight: Font.DemiBold
                            }

                            PillButton {
                                text: "Add startup apps"
                                onClicked: ShellState.openSettings("apps")
                            }
                        }
                    }
                }
            }
        }

        // ---------- the right-click menu ----------

        Item {
            anchors.fill: parent
            visible: root.menu !== null
            z: 10

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onPressed: root.menu = null
            }

            Rectangle {
                id: menuBox
                readonly property var task: root.menu ? root.menu.task : null
                width: 228
                height: menuColumn.implicitHeight + Theme.space1 * 2
                // Inside the window: to the left of the pointer near the right edge, above it near the bottom.
                x: root.menu ? Math.max(Theme.space2, Math.min(root.menu.x, parent.width - width - Theme.space2)) : 0
                y: root.menu ? (root.menu.y + height > parent.height - Theme.space2 ? Math.max(Theme.space2, root.menu.y - height) : root.menu.y) : 0
                radius: Theme.radiusMd
                color: Theme.surface200
                border.color: Theme.line
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuColumn
                    x: Theme.space1
                    y: Theme.space1
                    width: parent.width - Theme.space1 * 2
                    spacing: 0

                    Repeater {
                        model: root.menuItems(menuBox.task)

                        Item {
                            id: menuItem
                            required property var modelData
                            readonly property bool usable: modelData.enabled !== false
                            Layout.fillWidth: true
                            implicitHeight: modelData.separator ? 9 : 32

                            Rectangle {
                                visible: menuItem.modelData.separator === true
                                anchors.verticalCenter: parent.verticalCenter
                                x: Theme.space2
                                width: parent.width - Theme.space2 * 2
                                height: 1
                                color: Theme.line
                            }

                            Rectangle {
                                visible: !menuItem.modelData.separator
                                anchors.fill: parent
                                radius: Theme.radiusSm
                                color: itemMouse.containsMouse && menuItem.usable ? Theme.surface300 : "transparent"

                                UiText {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space3
                                    verticalAlignment: Text.AlignVCenter
                                    text: menuItem.modelData.text || ""
                                    color: !menuItem.usable ? Theme.inkMuted : menuItem.modelData.danger ? Theme.danger : Theme.ink
                                    opacity: menuItem.usable ? 1 : 0.6
                                    font.pixelSize: Theme.actionSize
                                }

                                MouseArea {
                                    id: itemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: menuItem.usable
                                    onClicked: {
                                        root.menu = null;
                                        menuItem.modelData.action();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
