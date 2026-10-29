pragma Singleton
// Window zones, as PowerToys' FancyZones: a layout of zones over each screen's work area;
// hold Shift while dragging a window and they show, and letting go over a zone fits the window
// to it. Near the line between zones it fills both; with Ctrl held too, every zone from the
// one where Ctrl went down to the one under the pointer. Layouts are templates or the user's
// own (ZoneEditor.qml), kept in settings.json as zones { enabled, layout, custom }.
//
// Hyprland reports no drags, so hyprland.lua passes on the left button (a global shortcut that
// does not take the click from apps) and Shift and Ctrl (over IPC, from its keyboard event);
// while the button is down with Shift held, the pointer and the focused window are polled,
// and only a window that actually moved counts as dragged.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property int gap: 8

    // Zones are fractions of the work area: { x, y, w, h }.
    readonly property var templates: [
        { id: "priority", name: "Priority", zones: [{ x: 0, y: 0, w: 0.25, h: 1 }, { x: 0.25, y: 0, w: 0.5, h: 1 }, { x: 0.75, y: 0, w: 0.25, h: 1 }] },
        { id: "columns2", name: "Two columns", zones: [{ x: 0, y: 0, w: 0.5, h: 1 }, { x: 0.5, y: 0, w: 0.5, h: 1 }] },
        { id: "columns3", name: "Three columns", zones: [{ x: 0, y: 0, w: 1 / 3, h: 1 }, { x: 1 / 3, y: 0, w: 1 / 3, h: 1 }, { x: 2 / 3, y: 0, w: 1 / 3, h: 1 }] },
        { id: "grid", name: "Grid", zones: [{ x: 0, y: 0, w: 0.5, h: 0.5 }, { x: 0.5, y: 0, w: 0.5, h: 0.5 }, { x: 0, y: 0.5, w: 0.5, h: 0.5 }, { x: 0.5, y: 0.5, w: 0.5, h: 0.5 }] },
        { id: "focus", name: "Main and side", zones: [{ x: 0, y: 0, w: 2 / 3, h: 1 }, { x: 2 / 3, y: 0, w: 1 / 3, h: 0.5 }, { x: 2 / 3, y: 0.5, w: 1 / 3, h: 0.5 }] },
        { id: "rows", name: "Rows", zones: [{ x: 0, y: 0, w: 1, h: 1 / 3 }, { x: 0, y: 1 / 3, w: 1, h: 1 / 3 }, { x: 0, y: 2 / 3, w: 1, h: 1 / 3 }] }
    ]

    readonly property var settings: (ShellSettings.values && ShellSettings.values.zones) || ({ enabled: true, layout: "priority", custom: [] })
    readonly property bool enabled: settings.enabled !== false
    readonly property string layoutId: settings.layout || "priority"
    readonly property var zones: {
        if (layoutId === "custom" && settings.custom && settings.custom.length) return settings.custom;
        const template = templates.find(candidate => candidate.id === layoutId);
        return (template || templates[0]).zones;
    }

    function setLayout(id, custom) {
        ShellSettings.update(values => {
            values.zones = Object.assign({ enabled: true }, values.zones || {}, { layout: id });
            if (custom) values.zones.custom = custom;
        });
    }

    function setEnabled(on) {
        ShellSettings.update(values => { values.zones = Object.assign({ layout: "priority", custom: [] }, values.zones || {}, { enabled: on }); });
    }

    // ---------- geometry ----------

    // A monitor's usable area (without the bar's strip), in global logical pixels.
    function workArea(monitor) {
        const reserved = (monitor.lastIpcObject && monitor.lastIpcObject.reserved) || [0, 0, 0, 0];
        const scale = monitor.scale || 1;
        return {
            x: monitor.x + reserved[0],
            y: monitor.y + reserved[1],
            width: monitor.width / scale - reserved[0] - reserved[2],
            height: monitor.height / scale - reserved[1] - reserved[3]
        };
    }

    // A zone's rectangle in an area: the gap around the outside and between zones.
    function zoneRect(zone, area) {
        const half = gap / 2;
        const inner = { x: area.x + half, y: area.y + half, width: area.width - gap, height: area.height - gap };
        return {
            x: Math.round(inner.x + zone.x * inner.width + half),
            y: Math.round(inner.y + zone.y * inner.height + half),
            width: Math.round(zone.w * inner.width - gap),
            height: Math.round(zone.h * inner.height - gap)
        };
    }

    function alpha(colour, opacity) {
        return Qt.rgba(colour.r, colour.g, colour.b, opacity);
    }

    function union(rects) {
        const left = Math.min(...rects.map(rect => rect.x));
        const top = Math.min(...rects.map(rect => rect.y));
        const right = Math.max(...rects.map(rect => rect.x + rect.width));
        const bottom = Math.max(...rects.map(rect => rect.y + rect.height));
        return { x: left, y: top, width: right - left, height: bottom - top };
    }

    // The zones the pointer picks: the one under it, both when it is near the line between two,
    // and with Ctrl everything spanning from the anchor zone to here.
    function pick(point, area) {
        const rects = zones.map(zone => zoneRect(zone, area));
        const near = 24;
        const picked = [];
        rects.forEach((rect, index) => {
            if (point.x >= rect.x - near && point.x <= rect.x + rect.width + near && point.y >= rect.y - near && point.y <= rect.y + rect.height + near) picked.push(index);
        });
        // Away from every line, only the zone it is in.
        const inside = rects.findIndex(rect => point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height);
        let chosen = picked.length > 1 && inside >= 0 && !nearLine(point, rects[inside], near) ? [inside] : picked;
        if (chosen.length === 0 && inside >= 0) chosen = [inside];
        if (ctrl && anchor.length && chosen.length) {
            const box = union(anchor.concat(chosen).map(index => rects[index]));
            chosen = rects.map((rect, index) => index).filter(index => {
                const rect = rects[index];
                return rect.x < box.x + box.width && rect.x + rect.width > box.x && rect.y < box.y + box.height && rect.y + rect.height > box.y;
            });
        }
        return chosen;
    }

    function nearLine(point, rect, near) {
        return point.x - rect.x < near || rect.x + rect.width - point.x < near || point.y - rect.y < near || rect.y + rect.height - point.y < near;
    }

    // ---------- dragging ----------

    property bool pointerDown: false
    property bool shift: false
    property bool ctrl: false
    property bool dragging: false      // the focused window has moved since the button went down
    property var start: null           // { address: [x, y] } of every window when the button went down
    property string dragged: ""        // the window that has moved since
    property var grab: null            // where the pointer holds it, once Shift takes the drag over
    property var cursor: ({ x: 0, y: 0 })
    property string monitorName: ""
    property var area: null
    property var selection: []         // zone indexes under the pointer
    property var anchor: []            // zone indexes where Ctrl went down
    readonly property bool showing: enabled && pointerDown && shift && dragging

    function buttonDown() {
        pointerDown = true;
        dragging = false;
        dragged = "";
        start = null;
        selection = [];
        anchor = [];
        if (enabled) startRead.running = true;
    }

    function buttonUp() {
        if (!pointerDown) return;
        if (showing && selection.length && dragged) snap(dragged, union(selection.map(index => zoneRect(zones[index], area))));
        dragged = "";
        grab = null;
        pointerDown = false;
        dragging = false;
        selection = [];
        anchor = [];
    }

    function setShift(down) {
        shift = down;
        if (!down) selection = [];
    }

    function setCtrl(down) {
        ctrl = down;
        anchor = down ? selection.slice() : [];
    }

    // Fits a window into a rectangle: out of maximised, floating, then sized and placed.
    function snap(address, rect) {
        const window = `window = "address:${address}"`;
        const toplevel = Array.from(Hyprland.toplevels.values).find(candidate => Taskbar.addressOf(candidate) === address);
        if (toplevel && toplevel.lastIpcObject && toplevel.lastIpcObject.fullscreen) Hyprland.dispatch(`hl.dsp.window.fullscreen({ mode = "maximized", ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.float({ action = "enable", ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.resize({ x = ${rect.width}, y = ${rect.height}, exact = true, ${window} })`);
        Hyprland.dispatch(`hl.dsp.window.move({ x = ${rect.x}, y = ${rect.y}, exact = true, ${window} })`);
        Taskbar.refresh();
    }

    // Where the pointer is and where every window is. The window being dragged is the one that
    // moved since the button went down (a Super + drag does not focus it, so the focused window
    // will not do).
    readonly property string probe: "hyprctl -j cursorpos; printf '\\n--\\n'; hyprctl -j clients"

    function parse(text) {
        const parts = text.split("\n--\n");
        let cursor = { x: 0, y: 0 };
        let places = {};
        try {
            cursor = JSON.parse(parts[0]);
            for (const client of JSON.parse(parts[1] || "[]")) places[client.address] = client.at;
        } catch (error) {
            // a half-written answer; the next poll has it
        }
        return { cursor: cursor, places: places };
    }

    Process {
        id: startRead
        command: ["sh", "-c", root.probe]
        stdout: StdioCollector {
            onStreamFinished: root.start = root.parse(this.text).places
        }
    }

    Process {
        id: poll
        command: ["sh", "-c", root.probe]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.pointerDown) return;
                const read = root.parse(this.text);
                root.cursor = read.cursor;
                if (root.start) {
                    for (const address of Object.keys(read.places)) {
                        const before = root.start[address];
                        const now = read.places[address];
                        if (before && now && (before[0] !== now[0] || before[1] !== now[1])) {
                            root.dragging = true;
                            root.dragged = address;
                        }
                    }
                }
                if (!root.dragging || !root.shift) {
                    root.grab = null;
                    return;
                }
                // Hyprland lets go of a window being dragged when Shift goes down, so from then
                // on it follows the pointer from here, keeping the spot it was held by.
                const place = read.places[root.dragged];
                if (place) {
                    if (!root.grab) root.grab = { x: read.cursor.x - place[0], y: read.cursor.y - place[1] };
                    const x = Math.round(read.cursor.x - root.grab.x);
                    const y = Math.round(read.cursor.y - root.grab.y);
                    if (x !== place[0] || y !== place[1]) Hyprland.dispatch(`hl.dsp.window.move({ x = ${x}, y = ${y}, exact = true, window = "address:${root.dragged}" })`);
                }
                const monitor = Array.from(Hyprland.monitors.values).find(candidate => {
                    const scale = candidate.scale || 1;
                    return read.cursor.x >= candidate.x && read.cursor.x < candidate.x + candidate.width / scale
                        && read.cursor.y >= candidate.y && read.cursor.y < candidate.y + candidate.height / scale;
                });
                if (!monitor) return;
                root.monitorName = monitor.name;
                root.area = root.workArea(monitor);
                root.selection = root.pick(read.cursor, root.area);
                if (root.ctrl && root.anchor.length === 0) root.anchor = root.selection.slice();
            }
        }
    }

    // While the button is down with Shift held: often enough for the zones to follow the pointer.
    Timer {
        interval: 40
        repeat: true
        running: root.enabled && root.pointerDown && root.shift
        onRunningChanged: if (running) Hyprland.refreshMonitors()
        onTriggered: if (!poll.running) poll.running = true
    }
}
