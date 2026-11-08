pragma Singleton
// Updates without a terminal. Every few hours (and when the Updates page asks) it counts
// what's waiting: Arch packages (checkupdates, which never touches the real package list),
// apps from the AUR (system/aur-update; the system half builds them in a sandbox), Flatpak
// apps, and Graphite's own commits; a notification says so once. Arch's news
// since the last update is listed, as some updates need a step by hand.
//
// install(): the system half runs as root in graphite-update.service (an administrator may
// start it without a password; its progress is /var/lib/graphite/update.json), the person's
// half (system/user-update.sh: their apps and Graphite) alongside it, apart from the shell
// (its progress is ~/.local/state/graphite/user-update), as an update of Graphite reloads
// the shell part way through; both are followed again after a reload. A new kernel asks
// for a restart. When Graphite's system parts (linux/system) have changed in an update,
// finishSystemParts() puts them in place, after the administrator's password.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string linux: Quickshell.shellDir + "/.."

    property bool checking: false
    property var packages: []      // ["mesa 24.1 -> 24.2", ...]
    property var aur: []           // the same, from the AUR
    property int appCount: 0
    property int deskCount: 0
    readonly property int total: packages.length + aur.length + appCount + deskCount
    property double lastChecked: 0
    property var news: []          // [{ title, link, date }] since the last update
    property bool partsChanged: false

    // The system half's progress, and the person's half.
    property var system: ({ state: "", step: "", percent: 0, time: 0, restart: false, note: "" })
    // What the system half couldn't update, for an hour after.
    readonly property string systemNote: system.note && Date.now() / 1000 - (system.time || 0) < 3600 ? system.note : ""
    property bool userRunning: false
    property string userStep: ""
    property string userNote: ""
    readonly property bool running: system.state === "running" || userRunning
    property bool started: false   // install() was pressed in this session
    property double userSince: 0   // when install() started the person's half (s)
    property double lastUpdated: 0 // when an update last finished (s)

    readonly property bool autoUpdates: ShellSettings.values ? !!ShellSettings.values.autoUpdates : false

    // Graphite's system parts in this copy, as install.sh records the ones it put in place.
    readonly property string partsHash: `cd -P "${linux}/system" && cat graphite-admin system-update aur-update pin-check boot-setup.sh *.service *.timer *.policy *.rules *.conf 2>/dev/null | sha256sum | cut -d' ' -f1`
    // A shell line for whatever needs the newest graphite-admin: the system parts put in place
    // first when this copy has moved on (one password covers both: polkit keeps it a while).
    readonly property string partsFirst: `[ "$(${partsHash})" = "$(cat /var/lib/graphite/system-parts 2>/dev/null)" ] || pkexec /usr/local/lib/graphite/graphite-admin install >/dev/null || exit 1`

    function check() {
        if (checking) return;
        checking = true;
        checker.running = true;
    }

    Process {
        id: checker
        command: ["bash", "-c", [
            "echo '== packages'; command -v checkupdates >/dev/null && checkupdates 2>/dev/null",
            `echo '== aur'; python3 -I "${root.linux}/system/aur-update" --check 2>/dev/null`,
            "echo '== apps'; flatpak remote-ls --updates --user --columns=application 2>/dev/null; flatpak remote-ls --updates --system --columns=application 2>/dev/null",
            // Never asking for a sign-in: the shell started on tty1, where git would wait for one forever.
            `echo '== desk'; repo="${Quickshell.shellDir}/../.."; GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes" timeout 60 git -C "$repo" fetch -q </dev/null 2>/dev/null && git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null`,
            `echo '== parts'; ${root.partsHash}; cat /var/lib/graphite/system-parts 2>/dev/null`,
            "echo '== news'; curl -s --max-time 8 https://archlinux.org/feeds/news/ | tr -d '\\n' | grep -o '<item>.*</item>' | sed 's/<item>/\\n/g' | sed -n 's|.*<title>\\(.*\\)</title>.*<link>\\(.*\\)</link>.*<pubDate>\\(.*\\)</pubDate>.*|\\1\\t\\2\\t\\3|p' | head -5",
            "echo '== last'; stat -c %Y /var/lib/graphite/update.json 2>/dev/null || date -d \"$(grep -a 'starting full system upgrade' /var/log/pacman.log | tail -1 | cut -c2-26)\" +%s 2>/dev/null"
        ].join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const sections = {};
                let current = "";
                for (const line of this.text.split("\n")) {
                    const heading = /^== (\w+)$/.exec(line);
                    if (heading) {
                        current = heading[1];
                        sections[current] = [];
                    } else if (current && line.trim()) sections[current].push(line.trim());
                }
                const before = root.total;
                root.packages = sections.packages || [];
                root.aur = sections.aur || [];
                root.appCount = (sections.apps || []).filter(line => line.includes(".")).length;
                root.deskCount = parseInt((sections.desk || ["0"])[0]) || 0;
                const parts = sections.parts || [];
                root.partsChanged = parts.length === 2 && parts[0] !== parts[1];
                const last = parseInt((sections.last || ["0"])[0]) || 0;
                root.news = (sections.news || []).map(line => line.split("\t"))
                    .filter(item => item.length === 3)
                    .map(item => ({ title: root.plainText(item[0]), link: item[1], date: new Date(item[2]) }))
                    .filter(item => item.date.getTime() / 1000 > last);
                root.lastChecked = Date.now();
                root.checking = false;
                if (root.total > 0 && root.total !== before && !root.running) {
                    Quickshell.execDetached(["notify-send", "-a", "Graphite", "-i", "software-update-available", "-h", "string:x-graphite-open:settings:updates",
                        "Updates available", root.total + (root.total === 1 ? " update is" : " updates are") + " available. Open Updates in the Control Panel to install."]);
                }
            }
        }
    }

    function plainText(text) {
        return text.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#39;/g, "'").replace(/&quot;/g, "\"");
    }

    // ---------- installing ----------

    function install() {
        if (running) return;
        started = true;
        system = { state: "running", step: "Starting", percent: 1, time: Date.now() / 1000, restart: false, note: "" };
        Quickshell.execDetached(["systemctl", "start", "--no-block", "graphite-update.service"]);
        userStep = "";
        userNote = "";
        userRunning = true;
        userSince = Date.now() / 1000;
        Quickshell.execDetached(["bash", root.linux + "/system/user-update.sh"]);
    }

    FileView {
        id: userProgress
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/graphite/user-update"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.readUserProgress(text())
    }

    // "START pid time", "STEP ..." and "NOTE ..." lines, "DONE time" at the end.
    function readUserProgress(text) {
        const lines = text.split("\n").filter(line => line);
        const start = (lines[0] || "").split(" ");
        const since = Number(start[2]) || 0;
        // Before this update's half has started, the last one's file doesn't count.
        if (start[0] !== "START" || since < userSince - 5) return;
        const last = prefix => {
            const found = lines.filter(line => line.startsWith(prefix));
            return found.length ? found[found.length - 1].slice(prefix.length) : "";
        };
        const done = last("DONE ");
        if (done) {
            lastUpdated = Math.max(lastUpdated, Number(done) || 0);
            // A note from an update over an hour ago is no longer news.
            userNote = Date.now() / 1000 - since < 3600 ? last("NOTE ") : "";
            userStep = "";
            if (userRunning) {
                userRunning = false;
                if (!running) finished();
            }
            return;
        }
        userNote = last("NOTE ");
        userStep = last("STEP ");
        // Still going, as after a reload: if it really is.
        if (!userRunning && !aliveCheck.running) {
            aliveCheck.command = ["kill", "-0", start[1]];
            aliveCheck.since = since;
            aliveCheck.running = true;
        }
    }

    Process {
        id: aliveCheck
        property double since: 0
        onExited: code => {
            root.userRunning = code === 0 && Date.now() / 1000 - since < 3600;
            if (!root.userRunning) root.userStep = "";
        }
    }

    FileView {
        id: progress
        path: "/var/lib/graphite/update.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const read = JSON.parse(text());
                // Before this session's update has written anything, an old "done" doesn't count.
                if (root.started && root.system.state === "running" && read.state !== "running" && read.time < root.system.time) return;
                const was = root.system.state === "running";
                root.system = read;
                if (was && read.state !== "running" && !root.userRunning) root.finished();
            } catch (error) {
                // being written
            }
        }
    }

    // Polled as well: the file is replaced (not written in place) on every step.
    Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: {
            progress.reload();
            userProgress.reload();
        }
    }

    // Graphite's own new files reload the shell by themselves.
    function finished() {
        lastUpdated = Math.max(lastUpdated, Date.now() / 1000);
        check();
    }

    function restart() {
        Quickshell.execDetached(["systemctl", "reboot"]);
    }

    function finishSystemParts() {
        Quickshell.execDetached(["sh", "-c", "pkexec /usr/local/lib/graphite/graphite-admin install && qs -c graphite ipc call settings reload"]);
    }

    function setAutoUpdates(on) {
        ShellSettings.set("autoUpdates", on);
        Quickshell.execDetached(["sh", "-c", `mkdir -p "$HOME/.config/graphite" && printf ${on ? "on" : "off"} > "$HOME/.config/graphite/auto-updates"`]);
    }

    // A first look a few minutes into the session, then every six hours.
    Timer {
        interval: 6 * 3600 * 1000
        repeat: true
        running: true
        onTriggered: root.check()
    }
    Timer {
        interval: 3 * 60 * 1000
        running: true
        onTriggered: root.check()
    }
}
