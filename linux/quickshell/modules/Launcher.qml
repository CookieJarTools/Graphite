// The launcher (the Super key): a search over the apps and the shell's commands, on the
// screen with the focused window. Arrows move, Enter opens, Escape or a click outside closes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.config
import qs.services

PanelWindow {
    id: root

    readonly property bool open: ShellState.launcherOpen
    property string query: ""
    property int selected: 0
    readonly property var results: search(query)

    readonly property var commands: [
        { name: "Lock", icon: "system-lock-screen-symbolic", command: ["loginctl", "lock-session"] },
        { name: "Sleep", icon: "system-suspend-symbolic", command: ["systemctl", "suspend"] },
        { name: "Sign out", icon: "system-log-out-symbolic", command: ["sh", "-c", "loginctl terminate-session \"$XDG_SESSION_ID\""] },
        { name: "Restart", icon: "system-reboot-symbolic", command: ["systemctl", "reboot"] },
        { name: "Shut down", icon: "system-shutdown-symbolic", command: ["systemctl", "poweroff"] },
        { name: "Reload the shell", icon: "view-refresh-symbolic", command: null }
    ]

    screen: {
        const focused = Hyprland.focusedMonitor;
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => focused && candidate.name === focused.name) || screens[0];
    }
    visible: open || card.opacity > 0
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-launcher"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (!open) return;
        input.text = "";
        selected = 0;
        input.forceActiveFocus();
    }

    // Name starts with it: best; a word starts with it: good; contains it: something.
    function score(text, query) {
        const value = (text || "").toLowerCase();
        if (!value) return 0;
        if (value.startsWith(query)) return 3;
        if (value.split(/[\s\-_.]+/).some(word => word.startsWith(query))) return 2;
        return value.includes(query) ? 1 : 0;
    }

    function search(text) {
        const query = text.trim().toLowerCase();
        const apps = Array.from(DesktopEntries.applications.values).filter(entry => !entry.noDisplay);
        const appRow = entry => ({ kind: "app", entry: entry, name: entry.name, icon: entry.icon, detail: entry.genericName || entry.comment || "" });
        if (!query) return apps.sort((first, second) => first.name.localeCompare(second.name)).map(appRow);

        const found = [];
        for (const entry of apps) {
            const keywords = Array.from(entry.keywords).some(keyword => score(keyword, query) > 0) ? 1 : 0;
            const rank = Math.max(score(entry.name, query) * 3, score(entry.genericName, query), keywords);
            if (rank > 0) found.push(Object.assign(appRow(entry), { rank: rank }));
        }
        for (const command of commands) {
            const rank = score(command.name, query) * 3;
            if (rank > 0) found.push({ kind: "command", command: command, name: command.name, icon: command.icon, detail: "Command", rank: rank });
        }
        return found.sort((first, second) => second.rank - first.rank || first.name.localeCompare(second.name)).slice(0, 50);
    }

    function run(item) {
        if (!item) return;
        ShellState.launcherOpen = false;
        if (item.kind === "app") Apps.launch(item.entry);
        else if (item.command.command) Quickshell.execDetached(item.command.command);
        else Quickshell.reload(true);
    }

    function move(delta) {
        if (results.length === 0) return;
        selected = Math.max(0, Math.min(results.length - 1, selected + delta));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durationBase : Theme.durationFast } }

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.launcherOpen = false
        }
    }

    Rectangle {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.18
        width: Math.min(Theme.launcherWidth, parent.width - Theme.space4 * 2)
        height: 520
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1
        clip: true
        opacity: root.open ? 1 : 0
        transform: Translate {
            y: root.open ? 0 : Theme.rise
            Behavior on y { NumberAnimation { duration: root.open ? Theme.durationBase : Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeEnter : Theme.easeExit } }
        }
        Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durationBase : Theme.durationFast; easing.type: Easing.BezierSpline; easing.bezierCurve: root.open ? Theme.easeEnter : Theme.easeExit } }

        MouseArea { anchors.fill: parent } // clicks on the card stay on it

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: Theme.space4
                Layout.rightMargin: Theme.space4
                spacing: Theme.space3

                Glyph { name: "system-search-symbolic" }

                TextInput {
                    id: input

                    Layout.fillWidth: true
                    color: Theme.ink
                    selectionColor: Theme.accentSoft
                    font.family: Theme.fontSans
                    font.pixelSize: 18
                    clip: true
                    onTextChanged: {
                        root.query = text;
                        root.selected = 0;
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down) root.move(1);
                        else if (event.key === Qt.Key_Up) root.move(-1);
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.run(root.results[root.selected]);
                        else if (event.key === Qt.Key_Escape) ShellState.launcherOpen = false;
                        else return;
                        event.accepted = true;
                    }

                    UiText {
                        anchors.fill: parent
                        visible: input.text.length === 0
                        text: "Search apps and commands"
                        color: Theme.inkMuted
                        font.pixelSize: 18
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.line
            }

            ListView {
                id: list

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: Theme.space2
                clip: true
                model: root.results
                currentIndex: root.selected
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: 44
                    radius: Theme.radiusSm
                    color: index === root.selected ? Theme.surface300 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        spacing: Theme.space3

                        IconImage {
                            implicitSize: 24
                            source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                        }

                        UiText {
                            text: row.modelData.name
                            font.weight: Font.Medium
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: row.modelData.detail
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: root.selected = row.index
                        onClicked: root.run(row.modelData)
                    }
                }
            }
        }
    }
}
