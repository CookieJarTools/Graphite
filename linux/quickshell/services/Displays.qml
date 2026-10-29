pragma Singleton
// Screens and the machine's Hyprland settings: each screen's size and refresh rate, scale,
// rotation, HDR and whether it is on (from `hyprctl monitors all -j`), night light
// (hyprsunset), brightness (brightnessctl, with a backlight), the mouse and touchpad, and the
// keyboard layout. Choices are kept in settings.json and written to
// ~/.config/graphite/desk.lua, which hyprland.lua runs last; Hyprland then reloads.
//
// A screen change is tried first: `pending` holds the old choice for 15 seconds, and unless
// keep() is called it goes back (Windows' "Keep these display settings?").

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // [{ name, description, width, height, refreshRate, scale, transform, modes: ["1920x1080@60"],
    //    disabled, hdr }]
    property var monitors: []
    readonly property var chosen: ShellSettings.values ? (ShellSettings.values.displays || {}) : ({})

    function refresh() {
        reader.running = true;
    }

    Process {
        id: reader
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(this.text).map(monitor => ({
                        name: monitor.name,
                        description: [monitor.make, monitor.model].filter(part => part).join(" ") || monitor.description || monitor.name,
                        width: monitor.width,
                        height: monitor.height,
                        refreshRate: monitor.refreshRate,
                        scale: monitor.scale,
                        transform: monitor.transform,
                        disabled: monitor.disabled,
                        hdr: /hdr/i.test(monitor.colorManagementPreset || ""),
                        modes: root.uniqueModes(monitor.availableModes || [])
                    }));
                } catch (error) {
                    root.monitors = [];
                }
            }
        }
    }

    // "1920x1080@59.94Hz" etc. as "1920x1080@59.94": the exact rate, as Hyprland needs it (a
    // rounded one matches no mode, so nothing changed); one per size and rounded rate, the
    // screen's own listing first; biggest first.
    function uniqueModes(modes) {
        const seen = [];
        const rounded = [];
        for (const mode of modes) {
            const match = /^(\d+)x(\d+)@([\d.]+)/.exec(mode);
            if (!match) continue;
            const key = match[1] + "x" + match[2] + "@" + Math.round(Number(match[3]));
            if (rounded.includes(key)) continue;
            rounded.push(key);
            seen.push(match[1] + "x" + match[2] + "@" + Number(match[3]).toFixed(2));
        }
        return seen.sort((first, second) => {
            const [a, b] = [first, second].map(mode => mode.split(/[x@]/).map(Number));
            return (b[0] * b[1] - a[0] * a[1]) || (b[2] - a[2]);
        });
    }

    function currentMode(monitor) {
        return monitor.width + "x" + monitor.height + "@" + Number(monitor.refreshRate).toFixed(2);
    }

    // ---------- changing a screen, with the chance to go back ----------

    property var pending: null   // { previous } while a change waits to be kept
    property int countdown: 0

    function change(name, key, value) {
        const previous = JSON.parse(JSON.stringify(chosen));
        ShellSettings.update(settings => {
            settings.displays = settings.displays || {};
            settings.displays[name] = Object.assign({}, settings.displays[name] || {});
            settings.displays[name][key] = value;
        });
        write();
        // HDR and turning a screen off ask too; a scale change is safe enough to keep at once.
        if (key === "scale") return;
        pending = { previous: previous };
        countdown = 15;
    }

    function keep() {
        pending = null;
        countdown = 0;
    }

    function revert() {
        if (!pending) return;
        const previous = pending.previous;
        pending = null;
        countdown = 0;
        ShellSettings.set("displays", previous);
        write();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.pending !== null
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) root.revert();
        }
    }

    // ---------- night light ----------

    readonly property bool nightLight: ShellSettings.values ? !!(ShellSettings.values.nightLight || {}).on : false
    readonly property int warmth: ShellSettings.values ? ((ShellSettings.values.nightLight || {}).temperature || 4500) : 4500

    function setNightLight(on) {
        ShellSettings.set("nightLight", { on: on, temperature: warmth });
        applyNightLight(on, warmth);
    }

    function setWarmth(temperature) {
        ShellSettings.set("nightLight", { on: nightLight, temperature: temperature });
        if (nightLight) applyNightLight(true, temperature);
    }

    function applyNightLight(on, temperature) {
        Quickshell.execDetached(["sh", "-c", on
            ? `pkill -x hyprsunset; sleep 0.2; exec hyprsunset -t ${Math.round(temperature)}`
            : "pkill -x hyprsunset"]);
    }

    // ---------- brightness (a laptop's own screen) ----------

    property bool hasBacklight: false
    property real brightness: 1

    Process {
        id: backlight
        command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -1 | grep -q . && brightnessctl -m info"]
        stdout: StdioCollector {
            onStreamFinished: {
                // name,class,current,percent,max
                const parts = this.text.trim().split(",");
                root.hasBacklight = parts.length >= 4;
                if (root.hasBacklight) root.brightness = parseInt(parts[3]) / 100;
            }
        }
    }

    function setBrightness(value) {
        brightness = Math.max(0.05, Math.min(1, value));
        Quickshell.execDetached(["brightnessctl", "-q", "set", Math.round(brightness * 100) + "%"]);
    }

    // ---------- the mouse, touchpad and keyboard ----------

    readonly property var input: ShellSettings.values ? (ShellSettings.values.input || {}) : ({})

    function setInput(key, value) {
        ShellSettings.update(settings => {
            settings.input = Object.assign({}, settings.input || {});
            settings.input[key] = value;
        });
        write();
    }

    function setKeyboard(layout) {
        ShellSettings.set("keyboard", layout);
        write();
    }

    // ---------- desk.lua ----------

    function lua(value) {
        return typeof value === "string" ? JSON.stringify(value) : String(value);
    }

    function write() {
        const settings = ShellSettings.values || {};
        const lines = [
            "-- Written by Graphite's Control Panel (services/Displays.qml): screens, mouse and keyboard.",
            "-- Changes here are replaced the next time something is changed there."
        ];
        for (const monitor of monitors) {
            const choice = (settings.displays || {})[monitor.name];
            if (!choice) continue;
            if (choice.enabled === false) {
                lines.push(`hl.monitor({ output = ${lua(monitor.name)}, disabled = true })`);
                continue;
            }
            const fields = [
                `output = ${lua(monitor.name)}`,
                `mode = ${lua(choice.mode || "preferred")}`,
                `position = "auto"`,
                `scale = ${choice.scale || 1}`,
                `transform = ${choice.transform || 0}`
            ];
            if (choice.hdr) fields.push(`bitdepth = 10`, `cm = "hdr"`);
            lines.push(`hl.monitor({ ${fields.join(", ")} })`);
        }
        const input = settings.input || {};
        const inputFields = [
            `sensitivity = ${Number(input.sensitivity || 0).toFixed(2)}`,
            `natural_scroll = ${!!input.naturalScroll}`,
            `touchpad = { natural_scroll = ${input.touchpadNaturalScroll !== false}, tap_to_click = ${input.tapToClick !== false} }`
        ];
        if (settings.keyboard) inputFields.push(`kb_layout = ${lua(settings.keyboard)}`);
        lines.push(`hl.config({ input = { ${inputFields.join(", ")} } })`);
        desk.setText(lines.join("\n") + "\n");
        reloadSoon.restart();
    }

    FileView {
        id: desk
        path: Quickshell.env("HOME") + "/.config/graphite/desk.lua"
        printErrors: false
        onSaved: reloadSoon.restart()
    }

    Timer {
        id: reloadSoon
        interval: 250
        onTriggered: {
            Quickshell.execDetached(["hyprctl", "reload"]);
            refreshSoon.restart();
        }
    }

    Timer {
        id: refreshSoon
        interval: 1200
        onTriggered: root.refresh()
    }

    // At the start of a session: the screens, the backlight, and night light if it was on.
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            root.refresh();
            backlight.running = true;
            if (root.nightLight) root.applyNightLight(true, root.warmth);
        }
    }
}
