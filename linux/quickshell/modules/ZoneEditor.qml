// Editing the window zones (Zones.qml), over the focused screen: pick a template, or make
// them your own. Click a zone to split it down the middle of where you clicked (Shift: across),
// drag a line between zones to move it, right-click a zone to join it with its neighbour.
// Save keeps the layout; Cancel or Escape leaves it as it was.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    readonly property bool open: ShellState.zoneEditorOpen
    readonly property var monitor: Hyprland.focusedMonitor
    property var draft: []
    property string draftLayout: "priority"
    readonly property real minimum: 0.08 // the smallest zone, as a share of the screen

    screen: {
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => monitor && candidate.name === monitor.name) || screens[0];
    }
    visible: open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-zones"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onOpenChanged: {
        if (!open) return;
        Hyprland.refreshMonitors();
        draft = JSON.parse(JSON.stringify(Zones.zones));
        draftLayout = Zones.layoutId;
        keys.forceActiveFocus();
    }

    // The work area in this window's coordinates.
    readonly property var area: {
        if (!monitor) return { x: 0, y: 0, width: width, height: height };
        const work = Zones.workArea(monitor);
        return { x: work.x - monitor.x, y: work.y - monitor.y, width: work.width, height: work.height };
    }

    function useTemplate(template) {
        draft = JSON.parse(JSON.stringify(template.zones));
        draftLayout = template.id;
    }

    function edited(zones) {
        draft = zones;
        draftLayout = "custom";
    }

    function save() {
        Zones.setLayout(draftLayout, draftLayout === "custom" ? draft : null);
        ShellState.zoneEditorOpen = false;
    }

    // ---------- editing ----------

    readonly property real eps: 0.001

    function fractionAt(point) {
        return { x: (point.x - area.x) / area.width, y: (point.y - area.y) / area.height };
    }

    function zoneAt(f) {
        return draft.findIndex(zone => f.x >= zone.x && f.x <= zone.x + zone.w && f.y >= zone.y && f.y <= zone.y + zone.h);
    }

    function split(index, f, across) {
        const zone = draft[index];
        const zones = draft.slice();
        if (across) {
            const cut = f.y - zone.y;
            if (cut < minimum || zone.h - cut < minimum) return;
            zones.splice(index, 1, { x: zone.x, y: zone.y, w: zone.w, h: cut }, { x: zone.x, y: f.y, w: zone.w, h: zone.h - cut });
        } else {
            const cut = f.x - zone.x;
            if (cut < minimum || zone.w - cut < minimum) return;
            zones.splice(index, 1, { x: zone.x, y: zone.y, w: cut, h: zone.h }, { x: f.x, y: zone.y, w: zone.w - cut, h: zone.h });
        }
        edited(zones);
    }

    // Joins a zone with a neighbour sharing a whole side with it.
    function merge(index) {
        const zone = draft[index];
        const same = (a, b) => Math.abs(a - b) < eps;
        const other = draft.findIndex((candidate, candidateIndex) => candidateIndex !== index && (
            (same(candidate.y, zone.y) && same(candidate.h, zone.h) && (same(candidate.x, zone.x + zone.w) || same(candidate.x + candidate.w, zone.x)))
            || (same(candidate.x, zone.x) && same(candidate.w, zone.w) && (same(candidate.y, zone.y + zone.h) || same(candidate.y + candidate.h, zone.y)))));
        if (other < 0) return;
        const neighbour = draft[other];
        const joined = {
            x: Math.min(zone.x, neighbour.x), y: Math.min(zone.y, neighbour.y),
            w: Math.max(zone.x + zone.w, neighbour.x + neighbour.w) - Math.min(zone.x, neighbour.x),
            h: Math.max(zone.y + zone.h, neighbour.y + neighbour.h) - Math.min(zone.y, neighbour.y)
        };
        edited(draft.filter((_, candidateIndex) => candidateIndex !== index && candidateIndex !== other).concat([joined]));
    }

    // A line between zones near the pointer: { vertical, at } (a fraction), or null.
    function lineAt(point) {
        const reach = 8;
        for (const zone of draft) {
            for (const edge of [zone.x, zone.x + zone.w]) {
                if (edge < eps || edge > 1 - eps) continue;
                const x = area.x + edge * area.width;
                const top = area.y + zone.y * area.height, bottom = top + zone.h * area.height;
                if (Math.abs(point.x - x) < reach && point.y >= top && point.y <= bottom) return { vertical: true, at: edge };
            }
            for (const edge of [zone.y, zone.y + zone.h]) {
                if (edge < eps || edge > 1 - eps) continue;
                const y = area.y + edge * area.height;
                const left = area.x + zone.x * area.width, right = left + zone.w * area.width;
                if (Math.abs(point.y - y) < reach && point.x >= left && point.x <= right) return { vertical: false, at: edge };
            }
        }
        return null;
    }

    // Moves a line, with every zone that touches it, keeping each zone a usable size.
    function moveLine(line, to) {
        const zones = draft.map(zone => Object.assign({}, zone));
        const start = line.vertical ? "x" : "y", size = line.vertical ? "w" : "h";
        let low = 0, high = 1;
        for (const zone of zones) {
            if (Math.abs(zone[start] + zone[size] - line.at) < eps) low = Math.max(low, zone[start] + minimum);
            if (Math.abs(zone[start] - line.at) < eps) high = Math.min(high, zone[start] + zone[size] - minimum);
        }
        const at = Math.max(low, Math.min(high, to));
        for (const zone of zones) {
            if (Math.abs(zone[start] + zone[size] - line.at) < eps) zone[size] = at - zone[start];
            else if (Math.abs(zone[start] - line.at) < eps) {
                zone[size] = zone[start] + zone[size] - at;
                zone[start] = at;
            }
        }
        edited(zones);
        return at;
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: ShellState.zoneEditorOpen = false
        Keys.onReturnPressed: root.save()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
    }

    // The zones, and the pointer on them.
    Item {
        x: root.area.x
        y: root.area.y
        width: root.area.width
        height: root.area.height

        Repeater {
            model: root.draft

            Rectangle {
                id: zone
                required property var modelData
                required property int index
                readonly property var rect: Zones.zoneRect(modelData, { x: 0, y: 0, width: root.area.width, height: root.area.height })
                x: rect.x
                y: rect.y
                width: rect.width
                height: rect.height
                radius: Theme.radiusLg
                color: Zones.alpha(Theme.surface200, 0.85)
                border.color: Theme.accent
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    UiText {
                        Layout.alignment: Qt.AlignHCenter
                        text: zone.index + 1
                        font.pixelSize: 36
                        font.weight: Font.DemiBold
                        color: Theme.accent
                    }

                    UiText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Math.round(zone.rect.width) + " × " + Math.round(zone.rect.height)
                        color: Theme.inkMuted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.identifierSize
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property var line: null
            property bool moved: false

            cursorShape: {
                const near = root.lineAt(Qt.point(mouseX + root.area.x, mouseY + root.area.y));
                return line || near ? ((line || near).vertical ? Qt.SplitHCursor : Qt.SplitVCursor) : Qt.PointingHandCursor;
            }

            onPressed: event => {
                moved = false;
                line = event.button === Qt.LeftButton ? root.lineAt(Qt.point(event.x + root.area.x, event.y + root.area.y)) : null;
            }
            onPositionChanged: event => {
                if (!line || !pressed) return;
                moved = true;
                const f = root.fractionAt(Qt.point(event.x + root.area.x, event.y + root.area.y));
                line = { vertical: line.vertical, at: root.moveLine(line, line.vertical ? f.x : f.y) };
            }
            onReleased: event => {
                const wasLine = line !== null;
                line = null;
                if (moved || wasLine) return;
                const f = root.fractionAt(Qt.point(event.x + root.area.x, event.y + root.area.y));
                const index = root.zoneAt(f);
                if (index < 0) return;
                if (event.button === Qt.RightButton) root.merge(index);
                else root.split(index, f, (event.modifiers & Qt.ShiftModifier) !== 0);
            }
        }
    }

    // The toolbar.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.area.y + Theme.space6
        width: toolbar.implicitWidth + Theme.space4 * 2
        height: toolbar.implicitHeight + Theme.space4 * 2
        radius: Theme.radiusLg
        color: Theme.surface200
        border.color: Theme.glassEdge
        border.width: 1

        ColumnLayout {
            id: toolbar
            anchors.centerIn: parent
            spacing: Theme.space3

            RowLayout {
                spacing: Theme.space3

                UiText {
                    text: "Window zones"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                MenuRow {
                    text: "Cancel"
                    onClicked: ShellState.zoneEditorOpen = false
                }

                Rectangle {
                    implicitWidth: saveLabel.implicitWidth + Theme.space4 * 2
                    implicitHeight: 30
                    radius: Theme.radiusControl
                    color: saveMouse.containsMouse ? Qt.lighter(Theme.accentFill, 1.08) : Theme.accentFill

                    UiText {
                        id: saveLabel
                        anchors.centerIn: parent
                        text: "Save"
                        color: Theme.onAccent
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: saveMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.save()
                    }
                }
            }

            RowLayout {
                spacing: Theme.space1

                Repeater {
                    model: Zones.templates.concat([{ id: "custom", name: "Custom" }])

                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.draftLayout === modelData.id
                        implicitWidth: chipText.implicitWidth + Theme.space3 * 2
                        implicitHeight: 28
                        radius: 14
                        color: on ? Theme.accentSoft : chipMouse.containsMouse ? Theme.surface300 : "transparent"
                        border.color: on ? Theme.accent : Theme.line
                        border.width: 1

                        UiText {
                            id: chipText
                            anchors.centerIn: parent
                            text: parent.modelData.name
                            font.pixelSize: Theme.hintSize
                            color: parent.on ? Theme.ink : Theme.inkMuted
                        }

                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (parent.modelData.zones) root.useTemplate(parent.modelData);
                                else if (Zones.settings.custom && Zones.settings.custom.length) root.edited(JSON.parse(JSON.stringify(Zones.settings.custom)));
                                else root.draftLayout = "custom";
                            }
                        }
                    }
                }
            }

            UiText {
                text: "Click a zone to split it, Shift+click to split the other way · Drag a line to resize · Right-click to merge zones"
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }
        }
    }
}
