pragma Singleton
// The storage clean-up (system/storage.py) for the Control Panel's Storage page: what fills the
// drives and what can go, read from ~/.local/state/graphite/storage.json. It looks again when
// the page opens and the last look is over an hour old, and once a week, with a notification
// when a clean-up would free a gigabyte or there are screenshots to look through. clean() does
// what the clean-up wizard chose (modules/CpCleanup.qml). Kept in settings.json as
// storage { remind }.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string script: Quickshell.shellDir + "/../system/storage.py"
    readonly property bool remind: !(ShellSettings.values && ShellSettings.values.storage && ShellSettings.values.storage.remind === false)

    // { time, drives: [{ mount, name, size, used, free, measured, top: [{ name, path, where, size }] }],
    //   caches: [{ id, title, detail, size, default, blocked, where }], system, shots: [{ path, name,
    //   size, time, video, thumb }], allShots: { count, size }, downloads: [{ path, name, size, time,
    //   folder }], chats: { count, size, ages: { "7": { count, size }, ... } }, bin, lastCleaned, lastFreed }
    property var results: null
    readonly property bool scanning: scanner.running
    property bool weekly: false     // this look is the weekly one, which may remind
    property bool cleaning: false
    property string step: ""
    property double freed: -1       // what the clean-up just done freed; -1 before one

    readonly property var drives: results ? results.drives || [] : []
    readonly property var caches: results ? results.caches || [] : []
    readonly property var shots: results ? results.shots || [] : []
    readonly property var downloads: results ? results.downloads || [] : []
    readonly property var chats: results && results.chats ? results.chats : ({ count: 0, size: 0, ages: {} })
    readonly property double system: results ? results.system || 0 : 0
    readonly property double bin: results ? results.bin || 0 : 0
    // What a clean-up with its first choices frees: the caches chosen to begin with, old updates
    // and logs, and chats over two weeks old (files for the Bin aren't counted).
    readonly property double easy: caches.filter(item => item.default && !item.blocked).reduce((sum, item) => sum + item.size, 0)
        + system + chatsOlderThan(14).size
    // And what there is to choose besides: the caches left off to begin with (build folders,
    // shaders, Fab downloads), and old or big downloads.
    readonly property double more: caches.filter(item => !item.default && !item.blocked).reduce((sum, item) => sum + item.size, 0)
        + downloads.reduce((sum, item) => sum + item.size, 0)

    function chatsOlderThan(days) {
        return (chats.ages || {})[String(days)] || { count: 0, size: 0 };
    }

    function setRemind(on) {
        ShellSettings.update(values => {
            values.storage = Object.assign({}, values.storage || {}, { remind: on });
        });
    }

    function scan(isWeekly) {
        if (scanner.running || cleaning) return;
        weekly = !!isWeekly;
        scanner.running = true;
    }

    function scanIfOld() {
        if (!results || Date.now() / 1000 - (results.time || 0) > 3600) scan(false);
    }

    Process {
        id: scanner
        command: ["nice", "-n", "10", "python3", "-I", root.script, "scan"]
        onExited: {
            answer.reload();
            if (root.weekly) remindAfter.restart();
        }
    }

    FileView {
        id: answer
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/graphite/storage.json"
        printErrors: false
        onLoaded: {
            try {
                root.results = JSON.parse(text());
            } catch (error) {
                // being written
            }
        }
    }

    Timer {
        id: remindAfter
        interval: 500
        onTriggered: {
            const count = root.shots.length;
            if (!root.remind || (root.easy < 1e9 && count < 10)) return;
            const found = [root.easy >= 1e9 ? Machine.size(root.easy) + " can be freed" : "",
                count >= 10 ? count + " new screenshots and recordings to look through" : ""].filter(part => part);
            Quickshell.execDetached(["notify-send", "-a", "Graphite", "-i", "drive-harddisk", "-h", "string:x-graphite-open:settings:storage",
                "Time for a clean-up", found.join(", and ") + ". See Control Panel > Storage."]);
        }
    }

    // Once a week, a few minutes after signing in and then on the hour, when the last look is
    // older than that.
    function scanIfDue() {
        if (!remind) return;
        if (Date.now() / 1000 - (results ? results.time || 0 : 0) > 7 * 86400 - 600) scan(true);
    }

    Timer {
        running: ShellSettings.loaded
        interval: 3600 * 1000
        repeat: true
        onTriggered: root.scanIfDue()
    }

    Timer {
        running: ShellSettings.loaded
        interval: 4 * 60 * 1000
        onTriggered: root.scanIfDue()
    }

    // request: { caches: [ids], files: [paths], chats: days (0 keeps them), system, bin, reviewed }
    function clean(request) {
        if (cleaning || scanner.running) return;
        cleaning = true;
        step = "Getting ready";
        freed = -1;
        cleaner.command = ["sh", "-c", "printf %s \"$1\" | python3 -I \"$2\" clean", "sh", JSON.stringify(request), script];
        cleaner.running = true;
    }

    Process {
        id: cleaner
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("STEP ")) root.step = line.slice(5);
                else if (line.startsWith("DONE ")) root.freed = Number(line.slice(5)) || 0;
            }
        }
        onExited: {
            root.cleaning = false;
            root.step = "";
            if (root.freed < 0) root.freed = 0;
            root.scan(false);
        }
    }

    Component.onCompleted: answer.reload()
}
