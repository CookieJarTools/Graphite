pragma Singleton
// The security sweep (system/security-sweep.py) for the Control Panel's Privacy & security
// page: run every day or week (or when asked), its findings read from
// ~/.local/state/graphite/security.json, a notification when something needs a look, and the
// fixes the page offers. Kept in settings.json as securitySweep { every, malware }.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property var settings: (ShellSettings.values && ShellSettings.values.securitySweep) || ({ every: "day", malware: false })
    readonly property string every: settings.every || "day"
    readonly property bool malware: !!settings.malware

    // { time (s), malware, checks: [{ id, title, state: ok|look|act|note, summary, details, fix }] }
    property var results: null
    // The finding whose fix is under way, until the look after it has finished (its button
    // says so: a first malware scan takes minutes).
    property string fixing: ""
    readonly property var checks: results ? results.checks || [] : []
    readonly property int toAct: checks.filter(item => item.state === "act").length
    readonly property int toLook: checks.filter(item => item.state === "look").length
    readonly property bool running: sweeper.running

    function set(key, value) {
        ShellSettings.update(values => {
            values.securitySweep = Object.assign({ every: "day", malware: false }, values.securitySweep || {}, { [key]: value });
        });
    }

    function sweep() {
        if (sweeper.running) return;
        sweeper.command = ["nice", "-n", "10", "python3", "-I", Quickshell.shellDir + "/../system/security-sweep.py"].concat(malware ? ["--malware"] : []);
        sweeper.running = true;
    }

    Process {
        id: sweeper
        onExited: {
            if (!installWait.running) root.fixing = "";
            answer.reload();
            notifyAfter.restart();
        }
    }

    FileView {
        id: answer
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/graphite/security.json"
        printErrors: false
        onLoaded: {
            try {
                root.results = JSON.parse(text());
            } catch (error) {
                root.results = null;
            }
        }
    }

    // Once a sweep has finished: a notification when something needs doing or a look.
    Timer {
        id: notifyAfter
        interval: 500
        onTriggered: {
            if (root.toAct + root.toLook === 0) return;
            const count = root.toAct + root.toLook;
            Quickshell.execDetached(["notify-send", "-a", "Graphite", "-i", root.toAct ? "security-low" : "security-medium",
                "Security sweep: " + count + (count === 1 ? " thing" : " things") + (root.toAct ? " to do" : " to look at"),
                "See Control Panel > Privacy & security."]);
        }
    }

    // Every day or week, a few minutes after signing in and then on the hour, when the last
    // sweep is older than that.
    Timer {
        running: ShellSettings.loaded && root.every !== "off"
        interval: 3600 * 1000
        repeat: true
        triggeredOnStart: false
        onTriggered: root.sweepIfDue()
    }

    Timer {
        running: ShellSettings.loaded && root.every !== "off"
        interval: 3 * 60 * 1000
        onTriggered: root.sweepIfDue()
    }

    function sweepIfDue() {
        const since = Date.now() / 1000 - (results ? results.time || 0 : 0);
        if (since > (every === "week" ? 7 : 1) * 86400 - 600) sweep();
    }

    // A finding's fix, then a fresh look where it changes the answer.
    function fix(item) {
        const action = item.fix ? item.fix.action : "";
        if (action === "updates") ShellState.openSettings("updates");
        else if (action === "accounts") ShellState.openSettings("accounts");
        else if (action === "startup") ShellState.openSettings("apps");
        else if (action === "firewall") {
            fixing = item.id;
            Machine.setFirewall(true);
            sweepSoon.restart();
        } else if (action === "install") {
            fixing = item.id;
            Desktop.installPackage(item.fix.package);
            installWait.waitingFor = item.fix.package;
            installWait.restart();
        } else if (action === "trash") {
            fixing = item.id;
            Quickshell.execDetached(["gio", "trash"].concat(item.fix.files || []));
            sweepSoon.restart();
        }
    }

    // For scripts: `qs -c graphite ipc call security sweep`.
    IpcHandler {
        target: "security"

        function sweep(): void { root.sweep(); }
    }

    Timer {
        id: sweepSoon
        interval: 4000
        onTriggered: root.sweep()
    }

    // An installed checker is used straight away.
    Timer {
        id: installWait
        property string waitingFor: ""
        interval: 5000
        repeat: true
        onTriggered: if (!Desktop.installingPackages[waitingFor]) {
            stop();
            root.sweep();
        }
    }
}
