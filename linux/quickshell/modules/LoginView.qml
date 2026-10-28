// What the login screen (greeter.qml) and the lock screen (LockScreen.qml) show: the backdrop,
// the time and date, the person (their initial and name) with a password field, a line for
// what went wrong (the card shakes on a wrong password), other people to pick when there are
// several, and Sleep, Restart and Shut down. It only shows; the screen using it checks the
// password (greetd or PAM) and sets busy, message and the like.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config

FocusScope {
    id: root

    // [{ name, full }]: people who can sign in; `user` is the one chosen.
    property var users: []
    property string user: ""
    property bool busy: false
    property string message: ""
    property bool messageIsError: false
    property bool showPower: true
    property string hint: "Enter your password"

    signal submit(string password)
    signal pickUser(string name)

    readonly property var person: users.find(candidate => candidate.name === user) || { name: user, full: user }
    readonly property string displayName: person.full || person.name

    function reset() {
        field.text = "";
        field.forceActiveFocus();
    }

    // The right password: the initial turns into a tick with a ring of light going out from it,
    // then the time and the card float up and fade, leaving the backdrop the desktop stands on.
    // `done` runs once it has played (about a second): unlock, or start the desktop.
    property var whenWelcomed: null
    property bool welcomed: false

    function welcome(text, done) {
        message = text;
        messageIsError = false;
        welcomed = true;
        whenWelcomed = done;
        field.text = "";
        welcomeAnimation.restart();
    }

    SequentialAnimation {
        id: welcomeAnimation
        ParallelAnimation {
            NumberAnimation { target: tick; property: "scale"; from: 0.4; to: 1; duration: 260; easing.type: Easing.OutBack }
            NumberAnimation { target: tick; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: initial; property: "opacity"; to: 0; duration: 120 }
            NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.2; duration: 700; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: 700; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 120 }
        ParallelAnimation {
            NumberAnimation { target: timeBlock; property: "opacity"; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: timeRise; property: "y"; to: -32; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: cardRise; property: "y"; to: -24; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: card; property: "scale"; to: 1.04; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: corners; property: "opacity"; to: 0; duration: 300 }
        }
        ScriptAction {
            script: {
                const done = root.whenWelcomed;
                root.whenWelcomed = null;
                if (done) done();
            }
        }
    }

    // Back to how it was, for the next time it shows (the lock screen is used again and again).
    function restore() {
        welcomeAnimation.stop();
        welcomed = false;
        timeBlock.opacity = 1;
        timeRise.y = 0;
        card.opacity = 1;
        card.scale = 1;
        cardRise.y = 0;
        corners.opacity = 1;
        tick.opacity = 0;
        initial.opacity = 1;
        ring.opacity = 0;
        message = "";
    }

    // A wrong password: the card shakes and the field empties.
    function refuse(text) {
        message = text;
        messageIsError = true;
        field.text = "";
        shake.restart();
        field.forceActiveFocus();
    }

    BackdropGlow { anchors.fill: parent }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------- the time ----------

    ColumnLayout {
        id: timeBlock
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.12
        spacing: 0
        transform: Translate { id: timeRise }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: 88
            font.weight: Font.DemiBold
        }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.date, "dddd d MMMM")
            color: Theme.inkMuted
            font.pixelSize: 18
        }
    }

    // ---------- the person and the password ----------

    ColumnLayout {
        id: card

        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.42
        spacing: Theme.space3
        transform: [
            Translate { id: nudge },
            Translate { id: cardRise }
        ]

        SequentialAnimation {
            id: shake
            NumberAnimation { target: nudge; property: "x"; to: -14; duration: 50 }
            NumberAnimation { target: nudge; property: "x"; to: 12; duration: 70 }
            NumberAnimation { target: nudge; property: "x"; to: -8; duration: 60 }
            NumberAnimation { target: nudge; property: "x"; to: 5; duration: 50 }
            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 40 }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 96
            implicitHeight: 96
            radius: 48
            color: Theme.accent

            // The ring of light that goes out on the right password.
            Rectangle {
                id: ring
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: width / 2
                color: "transparent"
                border.color: Theme.accent
                border.width: 3
                opacity: 0
            }

            UiText {
                id: initial
                anchors.centerIn: parent
                text: root.displayName.slice(0, 1).toUpperCase()
                color: Theme.onAccent
                font.pixelSize: 40
                font.weight: Font.DemiBold
            }

            // A tick, drawn: two strokes.
            Item {
                id: tick
                anchors.centerIn: parent
                width: 40
                height: 30
                opacity: 0

                Rectangle {
                    x: 4
                    y: 14
                    width: 16
                    height: 5
                    radius: 2.5
                    color: Theme.onAccent
                    rotation: 45
                    transformOrigin: Item.Right
                }

                Rectangle {
                    x: 14
                    y: 10
                    width: 28
                    height: 5
                    radius: 2.5
                    color: Theme.onAccent
                    rotation: -50
                    transformOrigin: Item.Left
                }
            }
        }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            text: root.displayName
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.space2
            implicitWidth: 340
            implicitHeight: 48
            radius: Theme.radiusLg
            color: Theme.surface200
            border.color: root.messageIsError && root.message ? Theme.danger : field.activeFocus ? Theme.accent : Theme.glassEdge
            border.width: field.activeFocus ? 2 : 1
            Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space1
                spacing: Theme.space2

                TextInput {
                    id: field

                    Layout.fillWidth: true
                    focus: true
                    enabled: !root.busy
                    echoMode: TextInput.Password
                    passwordCharacter: "●"
                    color: Theme.ink
                    selectionColor: Theme.accentSoft
                    font.family: Theme.fontSans
                    font.pixelSize: 16
                    clip: true
                    onTextChanged: if (text.length) root.message = ""
                    Keys.onReturnPressed: if (text.length && !root.busy) root.submit(text)
                    Keys.onEnterPressed: if (text.length && !root.busy) root.submit(text)

                    UiText {
                        anchors.fill: parent
                        visible: field.text.length === 0
                        text: root.busy ? "Signing in..." : root.hint
                        color: Theme.inkMuted
                        font.pixelSize: 16
                    }
                }

                // Go: the arrow, or a busy dot while it checks.
                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Theme.radiusMd
                    color: field.text.length && !root.busy ? (goMouse.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent) : "transparent"

                    Glyph {
                        anchors.centerIn: parent
                        visible: !root.busy
                        name: "go-next-symbolic"
                        opacity: field.text.length ? 1 : 0.4
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        visible: root.busy
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.accent
                        SequentialAnimation on opacity {
                            running: root.busy
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.2; duration: 400 }
                            NumberAnimation { to: 1; duration: 400 }
                        }
                    }

                    MouseArea {
                        id: goMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (field.text.length && !root.busy) root.submit(field.text)
                    }
                }
            }
        }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 20
            text: root.message
            color: root.messageIsError ? Theme.danger : Theme.inkMuted
        }

        // Others who can sign in.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.space4
            visible: root.users.length > 1
            spacing: Theme.space2

            Repeater {
                model: root.users.length > 1 ? root.users : []

                Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.name === root.user
                    implicitWidth: chip.implicitWidth + Theme.space3 * 2
                    implicitHeight: 36
                    radius: 18
                    color: on ? Theme.accentSoft : chipMouse.containsMouse ? Theme.surface300 : Theme.surface200
                    border.color: on ? Theme.accent : Theme.glassEdge
                    border.width: 1

                    RowLayout {
                        id: chip
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        Rectangle {
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: 11
                            color: Theme.accent

                            UiText {
                                anchors.centerIn: parent
                                text: (parent.parent.parent.modelData.full || parent.parent.parent.modelData.name).slice(0, 1).toUpperCase()
                                color: Theme.onAccent
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        UiText { text: parent.parent.modelData.full || parent.parent.modelData.name }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.pickUser(parent.modelData.name);
                            root.reset();
                        }
                    }
                }
            }
        }
    }

    // ---------- the corners ----------

    Item {
        id: corners
        anchors.fill: parent

        UiText {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Theme.space6
            text: "Graphite Desk"
            color: Theme.inkMuted
            font.weight: Font.DemiBold
        }

        RowLayout {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.space4
            visible: root.showPower
            spacing: Theme.space1

            Repeater {
                model: [
                    { name: "Sleep", glyph: "system-suspend-symbolic", command: ["systemctl", "suspend"] },
                    { name: "Restart", glyph: "system-reboot-symbolic", command: ["systemctl", "reboot"] },
                    { name: "Shut down", glyph: "system-shutdown-symbolic", command: ["systemctl", "poweroff"] }
                ]

                Rectangle {
                    required property var modelData
                    implicitWidth: powerRow.implicitWidth + Theme.space3 * 2
                    implicitHeight: 40
                    radius: Theme.radiusMd
                    color: powerMouse.containsMouse ? Theme.surface300 : "transparent"

                    RowLayout {
                        id: powerRow
                        anchors.centerIn: parent
                        spacing: Theme.space2
                        Glyph { name: parent.parent.modelData.glyph }
                        UiText {
                            text: parent.parent.modelData.name
                            color: Theme.inkMuted
                        }
                    }

                    MouseArea {
                        id: powerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Quickshell.execDetached(parent.modelData.command)
                    }
                }
            }
        }
    }
}
