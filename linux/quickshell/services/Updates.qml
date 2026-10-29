pragma Singleton
// Updates without a terminal. Every few hours (and when the Updates page asks) it counts
// what's waiting: Arch packages (checkupdates, which never touches the real package list),
// Flatpak apps, and Graphite Desk's own commits; a notification says so once. Arch's news
// since the last update is listed, as some updates need a step by hand.
//
// install(): the system half runs as root in graphite-update.service (an administrator may
// start it without a password; its progress is /var/lib/graphite/update.json), the person's
// half (system/user-update.sh: their apps and Graphite Desk) alongside it. A new kernel asks
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
    property int appCount: 0
    property int deskCount: 0
    readonly property int total: packages.length + appCount + deskCount
    property double lastChecked: 0
    property var news: []          // [{ title, link, date }] since the last update
    property bool partsChanged: false

    // The system half's progress, and the person's half.
    property var system: ({ state: "", step: "", percent: 0, time: 0, restart: false })
    property bool userRunning: false
    property string userStep: ""
    property string userNote: ""
    readonly property bool running: system.state === "running" || userRunning
    property bool started: false   // install() was pressed in this session

    readonly property bool autoUpdates: ShellSettings.values ? !!ShellSettings.values.autoUpdates : false

    // Graphite's system parts in this copy, as install.sh records the ones it put in place.
    readonly property string partsHash: `cd -P "${linux}/system" && cat graphite-admin system-update pin-check boot-setup.sh *.service *.timer *.policy *.rules 2>/dev/null | sha256sum | cut -d' ' -f1`
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
                    Quickshell.execDetached(["notify-send", "-a", "Graphite Desk", "-i", "software-update-available",
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
        system = { state: "running", step: "Starting", percent: 1, time: Date.now() / 1000, restart: false };
        Quickshell.execDetached(["systemctl", "start", "--no-block", "graphite-update.service"]);
        userStep = "";
        userNote = "";
        userRunning = true;
        userPart.running = true;
    }

    Process {
        id: userPart
        command: ["bash", root.linux + "/system/user-update.sh"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("STEP ")) root.userStep = line.slice(5);
                else if (line.startsWith("NOTE ")) root.userNote = line.slice(5);
            }
        }
        onExited: {
            root.userRunning = false;
            root.userStep = "";
            if (!root.running) root.finished();
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
                root.system = read;
                if (root.started && read.state !== "running" && !root.userRunning) root.finished();
            } catch (error) {
                // being written
            }
        }
    }

    // Polled as well: the file is replaced (not written in place) on every step.
    Timer {
        interval: 1000
        repeat: true
        running: root.started && root.running
        onTriggered: progress.reload()
    }

    function finished() {
        check();
        Quickshell.execDetached(["sh", "-c", "sleep 1; qs -c graphite ipc call settings reload"]);
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
