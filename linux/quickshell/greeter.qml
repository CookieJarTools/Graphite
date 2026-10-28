//@ pragma IconTheme Papirus-Dark
// The login screen: Graphite's own greeter for greetd, run by hypr/greeter.lua as
// `qs -p .../quickshell/greeter.qml` (so it shares the shell's theme and pieces). It lists the
// people who can sign in (from /etc/passwd), asks greetd to check the password, and starts
// the chosen person's desktop (start-hyprland).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import qs.config
import qs.modules

ShellRoot {
    id: root

    // People with a home and a login shell: [{ name, full }].
    property var users: []
    property string user: ""
    property string password: ""
    property bool busy: false

    // A refusal, or the welcome, for every screen's view to show.
    signal refused(string text)
    signal accepted()

    // Once the welcome has played, the person's desktop starts (once, whichever screen ends first).
    property bool launching: false

    function launchSession() {
        if (launching) return;
        launching = true;
        Greetd.launch(["start-hyprland"], ["XDG_SESSION_TYPE=wayland", "XDG_CURRENT_DESKTOP=Hyprland"], true);
    }

    FileView {
        id: passwd
        path: "/etc/passwd"
        blockLoading: true
    }

    Component.onCompleted: {
        users = passwd.text().split("\n").map(line => line.split(":")).filter(fields => {
            const uid = Number(fields[2]);
            return fields.length >= 7 && uid >= 1000 && uid < 60000 && !/(nologin|false)$/.test(fields[6]);
        }).map(fields => ({ name: fields[0], full: (fields[4] || "").split(",")[0] }));
        user = users.length ? users[0].name : "";
    }

    property bool justRefused: false

    function signIn(text) {
        if (!user) return;
        justRefused = false;
        password = text;
        busy = true;
        Greetd.createSession(user);
    }

    Connections {
        target: Greetd

        // greetd asks for the password (once, for a plain password login).
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.password);
                root.password = "";
            }
        }

        // greetd has already ended that attempt; cancelling it too only reports an error (which
        // would replace the message), so that one error is let pass.
        function onAuthFailure(message) {
            root.busy = false;
            root.password = "";
            root.justRefused = true;
            Greetd.cancelSession();
            root.refused("That password isn't right");
        }

        function onReadyToLaunch() {
            root.accepted();
        }

        function onError(error) {
            root.busy = false;
            if (root.justRefused) {
                root.justRefused = false;
                return;
            }
            root.refused("Couldn't sign in: " + error);
        }
    }

    // On every screen; only the first takes the keyboard.
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.backdrop
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            LoginView {
                id: view
                anchors.fill: parent
                focus: true
                users: root.users
                user: root.user
                busy: root.busy
                onSubmit: password => root.signIn(password)
                onPickUser: name => root.user = name
                Component.onCompleted: reset()

                Connections {
                    target: root
                    function onRefused(text) { view.refuse(text); }
                    function onAccepted() { view.welcome("Welcome", () => root.launchSession()); }
                }
            }
        }
    }
}
