// The administrator's password, when something asks for it (a Control Panel change, an app
// being installed, gaming's setup): Graphite's own prompt, as the shell is the polkit agent
// (Quickshell.Services.Polkit) in place of hyprpolkitagent, whose window crashed on opening.
// It dims the screen and takes the keyboard; Enter allows, Escape cancels, and a wrong password
// shakes the card and says so.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import qs.config

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
                    text: root.flow ? root.flow.message : ""
                    color: Theme.inkMuted
                    wrapMode: Text.WordWrap
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
                            text: "Your password"
                            color: Theme.inkMuted
                            font.pixelSize: 15
                        }
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.flow && root.flow.supplementaryMessage ? (root.flow.supplementaryIsError ? "That password is incorrect. Try again." : root.flow.supplementaryMessage) : ""
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
