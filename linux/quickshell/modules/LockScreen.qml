// The lock screen (Super+L, the launcher's Lock, before sleeping): the login screen's look
// (LoginView) over every screen through Wayland's session lock, so nothing else can be seen
// or reached until the password, checked by PAM, opens it again.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.config
import qs.services

Scope {
    id: root

    readonly property string user: Quickshell.env("USER") || ""
    property string fullName: ""
    property bool busy: false
    property string password: ""

    signal refused(string text)
    signal opened()
    signal accepted()

    function check(text) {
        password = text;
        busy = true;
        pam.start();
    }

    // The lock screen's own PAM service, which takes a PIN too (system/install.sh); the plain
    // login one where Graphite's system parts aren't in place.
    property string pamService: "login"
    property bool hasPin: false

    Process {
        running: true
        command: ["test", "-f", "/etc/pam.d/graphite-lock"]
        onExited: code => root.pamService = code === 0 ? "graphite-lock" : "login"
    }

    // Whether there is a PIN to ask for (checked each time it locks: it may have been set since).
    Process {
        id: pinCheck
        running: true
        command: ["test", "-d", "/var/lib/graphite/pins/" + root.user]
        onExited: code => root.hasPin = code === 0
    }

    PamContext {
        id: pam
        user: root.user
        config: root.pamService

        onPamMessage: {
            if (responseRequired) {
                respond(root.password);
                root.password = "";
            }
        }

        onCompleted: result => {
            root.busy = false;
            if (result === PamResult.Success) {
                root.accepted(); // the welcome plays, then it unlocks
            } else {
                root.refused("");
            }
        }

        onError: {
            root.busy = false;
            root.refused("Couldn't check the password");
        }
    }

    // The full name, from /etc/passwd, for the card.
    Process {
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1"]
        stdout: StdioCollector {
            onStreamFinished: root.fullName = this.text.trim()
        }
    }

    // Locked is remembered in a runtime file, so a shell that restarts (or crashes) while locked
    // locks again at once (hyprland.lua lets a new lock take over the old one).
    readonly property string marker: Quickshell.env("XDG_RUNTIME_DIR") + "/graphite-locked"

    FileView {
        id: markerFile
        path: root.marker
        printErrors: false
        blockLoading: true
    }

    Component.onCompleted: if (markerFile.text().trim() === "1") ShellState.locked = true

    readonly property bool isLocked: ShellState.locked
    onIsLockedChanged: {
        if (root.isLocked) pinCheck.running = true;
        Quickshell.execDetached(["sh", "-c", root.isLocked ? "echo 1 > \"$1\"" : "rm -f \"$1\"", "sh", root.marker]);
        if (root.isLocked) root.opened();
    }

    WlSessionLock {
        id: lock
        locked: ShellState.locked

        WlSessionLockSurface {
            color: Theme.backdrop

            LoginView {
                id: view
                anchors.fill: parent
                focus: true
                users: [{ name: root.user, full: root.fullName }]
                hasPin: root.hasPin
                user: root.user
                busy: root.busy
                showPower: false
                onSubmit: password => root.check(password)
                Component.onCompleted: reset()

                Connections {
                    target: root
                    function onRefused(text) { view.refuse(text); }
                    function onOpened() {
                        view.restore();
                        view.reset();
                    }
                    function onAccepted() { view.welcome("Welcome back", () => { ShellState.locked = false; }); }
                }
            }
        }
    }
}
