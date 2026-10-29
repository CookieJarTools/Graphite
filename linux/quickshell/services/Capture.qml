pragma Singleton
// The Snipping Tool, as on Windows (modules/CaptureTool.qml draws it): Print and Super+Shift+S
// open it over a still of the screen under the pointer, to take a screenshot of an area dragged
// out, of a window, or of the whole screen; Super+Shift+R opens it to record one instead, and
// stops the recording. A delay waits after choosing, so a menu can be opened first.
//
// system/screenshot.sh does the capturing. A screenshot is cut from the still, so it is the
// screen as it was when the tool opened (an open menu included); after a delay it's taken
// afresh. Recordings use wf-recorder (or gpu-screen-recorder); with neither, the tool offers to
// install wf-recorder from Arch's repositories.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/../system/screenshot.sh"
    readonly property string stillFile: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/graphite-capture.ppm"

    property bool open: false
    property string mode: "screenshot"  // or "record"
    property string kind: "rectangle"   // "window" or "screen"
    property int delay: 0               // seconds, after choosing
    readonly property var delays: [0, 3, 5, 10]
    // The screen under the pointer: { name, x, y, width, height, scale }, x to height logical
    // (global), and the windows on it, topmost first: [{ title, x, y, width, height }].
    property var monitor: null
    property var windows: []
    property string still: ""           // the still, as an image source (new for every opening)

    property int countdown: 0           // seconds before capturing or recording
    property var pending: null          // what the countdown ends in: { mode, rect }
    property bool recording: false
    property double recordingSince: 0
    property string recordingFile: ""
    property string recorder: ""        // the recorder installed, "" for none
    property bool installing: false

    function show(newMode) {
        if (newMode === "record" && recording) {
            stop();
            return;
        }
        if (recording || countdown > 0) return;
        mode = newMode;
        if (open) return;
        probe.running = true;
    }

    function cancel() {
        open = false;
        countdown = 0;
        pending = null;
    }

    function setKind(newKind) {
        kind = newKind;
        if (newKind === "screen") take({ x: 0, y: 0, width: monitor.width, height: monitor.height });
    }

    function nextDelay() {
        delay = delays[(delays.indexOf(delay) + 1) % delays.length];
    }

    // The window under a point of the screen (its own coordinates), or null.
    function windowAt(x, y) {
        if (!monitor) return null;
        const globalX = monitor.x + x;
        const globalY = monitor.y + y;
        return windows.find(window => globalX >= window.x && globalX < window.x + window.width && globalY >= window.y && globalY < window.y + window.height) || null;
    }

    // A part of the screen (its own coordinates), chosen: captured now, or after the delay.
    function take(rect) {
        if (mode === "record" && !recorder) return; // the tool offers to install one first
        const clipped = clip(rect);
        if (clipped.width < 2 || clipped.height < 2) return;
        open = false;
        if (delay > 0) {
            pending = { mode: mode, rect: clipped };
            countdown = delay;
            tick.restart();
            return;
        }
        if (mode === "record") startSoon.begin(clipped);
        else cut(clipped);
    }

    function clip(rect) {
        const x = Math.max(0, Math.round(rect.x));
        const y = Math.max(0, Math.round(rect.y));
        return {
            x: x,
            y: y,
            width: Math.min(monitor.width, Math.round(rect.x + rect.width)) - x,
            height: Math.min(monitor.height, Math.round(rect.y + rect.height)) - y
        };
    }

    // "X,Y WxH" across all screens, as grim and wf-recorder take it.
    function geometry(rect) {
        return `${monitor.x + rect.x},${monitor.y + rect.y} ${rect.width}x${rect.height}`;
    }

    // From the still, in its own pixels.
    function cut(rect) {
        const scale = monitor.scale;
        saver.command = ["bash", script, "cut", stillFile, String(Math.round(rect.x * scale)), String(Math.round(rect.y * scale)),
            String(Math.round(rect.width * scale)), String(Math.round(rect.height * scale))];
        saver.running = true;
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown > 0) return;
            tick.stop();
            // Once the countdown has left the screen.
            afterCountdown.start();
        }
    }

    Timer {
        id: afterCountdown
        interval: 250
        onTriggered: {
            const job = root.pending;
            root.pending = null;
            if (!job) return;
            if (job.mode === "record") root.startRecording(job.rect);
            else {
                saver.command = ["bash", root.script, "take", root.geometry(job.rect)];
                saver.running = true;
            }
        }
    }

    // A recording starts once the tool has left the screen.
    Timer {
        id: startSoon
        property var rect: null
        interval: 150
        function begin(newRect) {
            rect = newRect;
            restart();
        }
        onTriggered: root.startRecording(rect)
    }

    function startRecording(rect) {
        if (!recorder) return;
        const whole = rect.x === 0 && rect.y === 0 && rect.width === monitor.width && rect.height === monitor.height;
        // The video's sides in even pixels, as its encoding needs.
        const even = { x: rect.x, y: rect.y, width: rect.width - rect.width % 2, height: rect.height - rect.height % 2 };
        recordingFile = "";
        recorderProcess.command = whole ? ["bash", script, "record", "output", monitor.name] : ["bash", script, "record", "area", geometry(even)];
        recorderProcess.running = true;
        recording = true;
        recordingSince = Date.now();
    }

    function stop() {
        if (recording) recorderProcess.signal(2); // SIGINT: the recorder finishes the file
    }

    function installRecorder() {
        installing = true;
        installer.running = true;
    }

    // ---------- processes ----------

    // Where the pointer is, the screens and the windows; then the still of that screen.
    Process {
        id: probe
        command: ["sh", "-c", "hyprctl -j cursorpos; printf '\\n--\\n'; hyprctl -j monitors; printf '\\n--\\n'; hyprctl -j clients; printf '\\n--\\n'; command -v wf-recorder gpu-screen-recorder | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("\n--\n");
                try {
                    const cursor = JSON.parse(parts[0]);
                    const monitors = JSON.parse(parts[1]).map(monitor => {
                        const turned = monitor.transform % 2 === 1;
                        return {
                            name: monitor.name,
                            x: monitor.x,
                            y: monitor.y,
                            width: Math.round((turned ? monitor.height : monitor.width) / monitor.scale),
                            height: Math.round((turned ? monitor.width : monitor.height) / monitor.scale),
                            scale: monitor.scale,
                            workspaces: [monitor.activeWorkspace.id, monitor.specialWorkspace.id].filter(id => id)
                        };
                    });
                    const monitor = monitors.find(candidate => cursor.x >= candidate.x && cursor.x < candidate.x + candidate.width
                        && cursor.y >= candidate.y && cursor.y < candidate.y + candidate.height) || monitors[0];
                    root.monitor = monitor;
                    root.windows = JSON.parse(parts[2])
                        .filter(client => client.mapped && !client.hidden && monitor.workspaces.includes(client.workspace.id))
                        .sort((first, second) => first.focusHistoryID - second.focusHistoryID)
                        .map(client => ({ title: client.title || client.class, x: client.at[0], y: client.at[1], width: client.size[0], height: client.size[1] }));
                    root.recorder = (parts[3] || "").trim().split("/").pop();
                } catch (error) {
                    return;
                }
                stiller.command = ["bash", root.script, "still", root.monitor.name, root.stillFile];
                stiller.running = true;
            }
        }
    }

    Process {
        id: stiller
        onExited: code => {
            if (code !== 0) return;
            root.still = "file://" + root.stillFile + "?" + Date.now();
            root.open = true;
        }
    }

    Process {
        id: saver
    }

    Process {
        id: recorderProcess
        stdout: SplitParser {
            onRead: line => { if (!root.recordingFile) root.recordingFile = line.trim(); }
        }
        onExited: code => {
            root.recording = false;
            if (root.recordingFile) Quickshell.execDetached(["bash", root.script, "recorded", root.recordingFile]);
        }
    }

    // wf-recorder from Arch's repositories, after an administrator's password.
    Process {
        id: installer
        command: ["sh", "-c", "pkexec /usr/local/lib/graphite/graphite-admin package-install wf-recorder; command -v wf-recorder gpu-screen-recorder | head -1"]
        stdout: StdioCollector {
            onStreamFinished: root.recorder = this.text.trim().split("/").pop()
        }
        onExited: root.installing = false
    }
}
