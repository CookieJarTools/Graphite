// The administrator's password (or their PIN), when something asks for it (a Control Panel
// change, an app being installed, gaming's setup): Graphite's own prompt, as the shell is the
// polkit agent (Quickshell.Services.Polkit) in place of hyprpolkitagent, whose window crashed
// on opening.
// It dims the screen, plays the system sound for it, and takes the keyboard; Enter allows,
// Escape cancels, and a wrong password shakes the card and says so. What is being allowed is
// said in plain words: polkit's own message names a program and its arguments, so the prompt
// reads the command that asked (the newest pkexec) or goes by the kind of request, and keeps
// the original under Details.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.config
import qs.services

Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    readonly property var flow: agent.flow
    readonly property bool asking: agent.isActive && flow !== null

    Connections {
        target: root.flow
        ignoreUnknownSignals: true

        function onAuthenticationFailed() {
            field.text = "";
            shake.restart();
        }
    }

    onAskingChanged: if (asking) {
        field.text = "";
        field.forceActiveFocus();
        pinCheck.running = true;
        root.command = "";
        root.showDetails = false;
        asker.running = true;
        Sounds.play("password");
    }

    // ---------- what is being allowed ----------

    property string command: "" // the pkexec command that asked, if one did
    property bool showDetails: false

    Process {
        id: asker
        command: ["sh", "-c", "pid=$(pgrep -n -x pkexec) && tr '\\0' ' ' < /proc/$pid/cmdline"]
        stdout: StdioCollector { onStreamFinished: root.command = this.text.trim() }
    }

    readonly property string what: describe(flow ? flow.actionId : "", command)

    // Graphite's administrator helper (system/graphite-admin) by its verbs, other programs by
    // name, and requests from the system's services by their kind.
    function describe(action, command) {
        const words = command.split(/\s+/).filter(Boolean);
        const at = words.findIndex(word => word.endsWith("/graphite-admin"));
        if (at >= 0) {
            const [verb, first, second] = words.slice(at + 1);
            const app = id => { const entry = DesktopEntries.byId(id); return entry ? entry.name : id; };
            return ({
                "firewall": first === "off" ? "Turn the firewall off" : "Turn the firewall on",
                "user-add": "Add " + (first || "a person") + " to this computer",
                "user-remove": "Remove " + first + " and their files",
                "user-password": "Change " + first + "'s password",
                "user-fullname": "Change " + first + "'s name",
                "user-admin": second === "yes" ? "Make " + first + " an administrator" : "Make " + first + " a standard user",
                "pin": "Set " + first + "'s sign-in PIN",
                "hint": "Set " + first + "'s password hint",
                "fix-home": "Repair " + first + "'s home folder",
                "flatpak-update": "Update apps for everyone",
                "format": "Format a partition (" + first + ")",
                "erase": "Erase a drive (" + first + ")",
                "package-install": "Install " + words.slice(at + 2).join(", "),
                "package-remove": "Uninstall " + first,
                "flatpak-remove": "Uninstall " + app(first),
                "clean": "Free up space",
                "install": "Update Graphite Desk's system parts",
                "dynamic-disks": "Open a Windows dynamic disk"
            })[verb] || "Change a system setting";
        }
        if (/gaming\.sh/.test(command)) return "Set up gaming";
        if (words[0] === "pkexec") {
            const program = words.slice(1).find(word => !word.includes("=") && word !== "env") || "";
            const entry = DesktopEntries.applications.values.find(candidate => candidate.command && candidate.command[0] && candidate.command[0].split("/").pop() === program.split("/").pop());
            return "Run " + (entry ? entry.name : program.split("/").pop()) + " as administrator";
        }
        const kinds = [
            [/^org\.freedesktop\.udisks2\..*(unlock|encrypted)/, "Unlock an encrypted drive"],
            [/^org\.freedesktop\.udisks2\..*(power-off|eject)/, "Eject a drive"],
            [/^org\.freedesktop\.udisks2\..*mount/, "Connect a drive"],
            [/^org\.freedesktop\.udisks2\./, "Change a drive"],
            [/^org\.freedesktop\.NetworkManager\./, "Change network settings"],
            [/^org\.freedesktop\.timedate1\./, "Change the date and time"],
            [/^org\.freedesktop\.hostname1\./, "Rename this computer"],
            [/^org\.freedesktop\.locale1\./, "Change the language or keyboard"],
            [/^org\.freedesktop\.login1\./, "Restart, shut down or sleep"],
            [/^org\.freedesktop\.systemd1\./, "Start or stop a system service"],
            [/^org\.freedesktop\.(packagekit|Flatpak)\./, "Install or update apps"],
            [/^org\.bluez/, "Change Bluetooth"],
            [/^org\.graphite\./, "Change a system setting"]
        ];
        const kind = kinds.find(pair => pair[0].test(action));
        return kind ? kind[1] : "Make a change that needs an administrator";
    }

    // With a sign-in PIN, the PIN works here too (system/install.sh puts pin-check in front of
    // polkit's password check).
    property bool hasPin: false

    Process {
        id: pinCheck
        command: ["sh", "-c", "test -d \"/var/lib/graphite/pins/$USER\""]
        onExited: code => root.hasPin = code === 0
    }

    function allow() {
        if (!flow || !field.text.length) return;
        flow.submit(field.text);
        field.text = "";
    }

    function cancel() {
        if (flow) flow.cancelAuthenticationRequest();
    }

    PanelWindow {
        id: window

        visible: root.asking
        screen: Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-password"
        WlrLayershell.keyboardFocus: root.asking ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
        }

        Rectangle {
            id: card

            anchors.centerIn: parent
            width: 420
            implicitHeight: content.implicitHeight + Theme.space6 * 2
            radius: Theme.radiusLg
            color: Theme.surface200
            border.color: Theme.glassEdge
            border.width: 1
            transform: Translate { id: nudge }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: nudge; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: nudge; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: nudge; property: "x"; to: -6; duration: 60 }
                NumberAnimation { target: nudge; property: "x"; to: 0; duration: 50 }
            }

            ColumnLayout {
                id: content
                x: Theme.space6
                y: Theme.space6
                width: parent.width - Theme.space6 * 2
                spacing: Theme.space3

                Rectangle {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Theme.radiusMd
                    color: Theme.accentSoft

                    Glyph {
                        anchors.centerIn: parent
                        name: "system-lock-screen-symbolic"
                        tint: Theme.accent
                        implicitSize: 20
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    text: "Allow this change?"
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                UiText {
                    Layout.fillWidth: true
                    text: root.what
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }

                UiText {
                    Layout.fillWidth: true
                    text: root.hasPin ? "An administrator's PIN or password is needed." : "An administrator's password is needed."
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }

                // Polkit's own words, and the command that asked.
                UiText {
                    text: root.showDetails ? "Hide details" : "Show details"
                    color: detailsMouse.containsMouse ? Theme.ink : Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    font.underline: detailsMouse.containsMouse

                    MouseArea {
                        id: detailsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showDetails = !root.showDetails
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    visible: root.showDetails
                    text: [root.flow ? root.flow.message : "", root.command, root.flow ? root.flow.actionId : ""].filter(Boolean).join("\n")
                    color: Theme.inkMuted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                    wrapMode: Text.WrapAnywhere
                    elide: Text.ElideNone
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space2
                    implicitHeight: 44
                    radius: Theme.radiusMd
                    color: Theme.surface100
                    border.color: root.flow && root.flow.supplementaryIsError ? Theme.danger : field.activeFocus ? Theme.accent : Theme.line
                    border.width: field.activeFocus ? 2 : 1

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space3
                        anchors.rightMargin: Theme.space3
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        color: Theme.ink
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                        clip: true
                        focus: root.asking
                        Keys.onReturnPressed: root.allow()
                        Keys.onEnterPressed: root.allow()
                        Keys.onEscapePressed: root.cancel()

                        UiText {
                            anchors.fill: parent
                            visible: field.text.length === 0
                            text: root.hasPin ? "Your PIN or password" : "Your password"
                            color: Theme.inkMuted
                            font.pixelSize: 15
                        }
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.flow && root.flow.supplementaryMessage ? (root.flow.supplementaryIsError ? (root.hasPin ? "That isn't right. Try again." : "That password is incorrect. Try again.") : root.flow.supplementaryMessage) : ""
                    color: root.flow && root.flow.supplementaryIsError ? Theme.danger : Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space2
                    spacing: Theme.space2

                    Item { Layout.fillWidth: true }

                    PillButton {
                        text: "Cancel"
                        onClicked: root.cancel()
                    }

                    PillButton {
                        primary: true
                        text: "Allow"
                        enabled: field.text.length > 0
                        onClicked: root.allow()
                    }
                }
            }
        }
    }
}
