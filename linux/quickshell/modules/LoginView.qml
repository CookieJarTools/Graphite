// What the login screen (greeter.qml) and the lock screen (LockScreen.qml) show, on the
// wallpaper with a slightly stronger glow:
//   Arriving: a large clock and the date at the top, and the person at the bottom (their
//     initial, their name and a pill-shaped password box), each rising into place as a blur
//     clears, the person a moment after the clock. Any key (Space) or a click goes to the box.
//   Checking: a line in the accent sweeps around the picture.
//   Right: the ring closes into a full circle, the clock and the form lift away, the glow
//     spreads and "Good evening, Joe" rises in; then `done` (unlock, or start the desktop).
//   Wrong: the ring flashes red, the box shakes and settles, "That password is incorrect. 2
//     tries left." fades in, and what was typed is selected to type over. After three, the box
//     locks for 30 seconds behind a draining red bar, then the person's password hint shows
//     (/var/lib/graphite/hints/<name>, set in the Control Panel).
//   Caps Lock on: it says so under the box.
// The corner holds the network and (on the login screen) the power menu. Left alone, it falls
// back to the clock. It only shows: the screen using it checks the password (greetd or PAM),
// sets busy, and calls refuse("") for a wrong password, refuse(text) for anything else.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

FocusScope {
    id: root

    // [{ name, full }]: people who can sign in; `user` is the one chosen.
    property var users: []
    property string user: ""
    property bool busy: false
    property bool showPower: true

    signal submit(string password)
    signal pickUser(string name)

    readonly property var person: users.find(candidate => candidate.name === user) || { name: user, full: user }
    readonly property string displayName: person.full || person.name

    property bool curtain: true
    property bool welcomed: false
    property bool powerMenu: false
    property string message: ""
    property bool messageIsError: false
    property int failures: 0
    property int lockedFor: 0 // seconds left of the lock-out after three wrong passwords
    property bool showHint: false
    property bool capsLock: false

    // A PIN (4 digits) when the person has one: asked for instead of the password, signing in
    // on the fourth digit. Three wrong and it rests (10 minutes, as the PAM check does too);
    // the password is asked instead.
    property bool hasPin: false
    property bool usePin: false
    property int pinFailures: 0
    property bool pinResting: false
    onHasPinChanged: usePin = hasPin && !pinResting

    Timer {
        id: pinRest
        interval: 10 * 60 * 1000
        onTriggered: {
            root.pinResting = false;
            root.pinFailures = 0;
        }
    }

    function switchToPin(on) {
        usePin = on && hasPin && !pinResting;
        field.text = "";
        message = "";
        field.forceActiveFocus();
    }

    readonly property int allowed: 3
    readonly property int lockout: 30

    // ---------- what the screens using it call ----------

    function reset() {
        field.text = "";
        message = "";
        usePin = hasPin && !pinResting;
        curtain = true;
        powerMenu = false;
        root.forceActiveFocus();
    }

    function refuse(text) {
        field.selectAll();
        field.forceActiveFocus();
        ringFlash.restart();
        shake.restart();
        if (text) {
            say(text, true);
            return;
        }
        if (usePin) {
            field.text = "";
            pinFailures += 1;
            const pinLeft = allowed - pinFailures;
            if (pinLeft > 0) {
                say("That PIN is incorrect. " + pinLeft + (pinLeft === 1 ? " try left." : " tries left."), true);
                return;
            }
            pinResting = true;
            pinRest.restart();
            usePin = false;
            say("Too many wrong PINs. Sign in with your password.", true);
            return;
        }
        failures += 1;
        const left = allowed - failures;
        if (left > 0) {
            say("That password is incorrect. " + left + (left === 1 ? " try left." : " tries left."), true);
            return;
        }
        say("", true);
        lockedFor = lockout;
        drain.restart();
    }

    function welcome(text, done) {
        whenWelcomed = done;
        welcomed = true;
        message = "";
        field.text = "";
        failures = 0;
        welcomeAnimation.restart();
    }

    // Back to how it was, for the next time it shows (the lock screen is used again and again).
    function restore() {
        welcomeAnimation.stop();
        welcomed = false;
        whenWelcomed = null;
        form.opacity = 1;
        formRise.y = 0;
        clockBlock.opacity = 1;
        greeting.opacity = 0;
        greetingRise.y = 24;
        corners.opacity = 1;
        ring.sweep = 0;
        glow.spread = 1;
        message = "";
        enter();
    }

    Component.onCompleted: enter()

    // ---------- the curtain ----------

    function lift(text) {
        if (!curtain) return;
        curtain = false;
        field.forceActiveFocus();
        if (text) field.text += text;
        idle.restart();
    }

    Keys.onPressed: event => {
        if (!curtain) return;
        lift(event.text && event.text.charCodeAt(0) > 32 ? event.text : "");
        event.accepted = true;
    }

    // A minute with nothing typed: back to the clock.
    Timer {
        id: idle
        interval: 60000
        running: !root.curtain && !root.busy && !root.welcomed && root.lockedFor === 0
        onTriggered: {
            if (field.text.length) restart();
            else root.reset();
        }
    }

    function say(text, error) {
        messageIsError = error;
        message = text;
        messageFade.restart();
    }

    function greetingText() {
        const hour = new Date().getHours();
        const part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
        const first = displayName.split(" ")[0];
        return first ? part + ", " + first : part;
    }

    // The person's password hint, readable by the login screen.
    FileView {
        id: hintFile
        path: root.user ? "/var/lib/graphite/hints/" + root.user : ""
        printErrors: false
    }
    readonly property string hint: hintFile.text().trim()

    // Caps Lock, from the keyboard's light, while the box is up.
    Process {
        id: caps
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.capsLock = /[1-9]/.test(this.text) }
    }
    Timer {
        interval: 700
        repeat: true
        running: !root.curtain && !root.welcomed
        triggeredOnStart: true
        onTriggered: caps.running = true
    }

    // The lock-out after three wrong passwords: the bar drains, then the hint shows.
    NumberAnimation {
        id: drain
        target: lockBar
        property: "fraction"
        from: 1
        to: 0
        duration: root.lockout * 1000
        onFinished: {
            root.lockedFor = 0;
            root.failures = 0;
            root.showHint = root.hint.length > 0;
            root.say("", false);
            field.forceActiveFocus();
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.lockedFor > 0
        onTriggered: root.lockedFor = Math.max(0, root.lockedFor - 1)
    }

    // ---------- the backdrop ----------

    BackdropGlow {
        id: glow
        anchors.fill: parent
        strength: Theme.dark ? 0.3 : 0.16
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.powerMenu = false;
            if (root.curtain) root.lift("");
            else field.forceActiveFocus();
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // ---------- arriving ----------

    // The clock and the person each rise 16 px into place as an 8 px blur clears, the person a
    // moment after the clock: when it locks, and when the login screen first shows.
    function enter() {
        entry.restart();
    }

    ParallelAnimation {
        id: entry
        ScriptAction {
            script: {
                for (const block of [clockBlock, form]) {
                    block.opacity = 0;
                    block.lift = Theme.move(16);
                    block.haze = Theme.reducedMotion ? 0 : 1;
                }
            }
        }
        NumberAnimation { target: clockBlock; property: "opacity"; from: 0; to: 1; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { target: clockBlock; property: "lift"; from: Theme.move(16); to: 0; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        NumberAnimation { target: clockBlock; property: "haze"; from: Theme.reducedMotion ? 0 : 1; to: 0; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        SequentialAnimation {
            PauseAnimation { duration: Theme.lockStagger }
            ParallelAnimation {
                NumberAnimation { target: form; property: "opacity"; from: 0; to: 1; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                NumberAnimation { target: form; property: "lift"; from: Theme.move(16); to: 0; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                NumberAnimation { target: form; property: "haze"; from: Theme.reducedMotion ? 0 : 1; to: 0; duration: Theme.durationLock; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }
        }
    }

    // ---------- the clock, at the top ----------

    ColumnLayout {
        id: clockBlock
        property real lift: 0
        property real haze: 0   // 1 is an 8 px blur
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.1 + lift
        spacing: 0
        layer.enabled: haze > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 16
            blur: clockBlock.haze * 0.5
        }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            font.pixelSize: Theme.clockSize
            font.weight: Font.Light
            font.letterSpacing: -Theme.clockSize * 0.04
            font.features: { "tnum": 1 }
        }

        UiText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.date, "dddd d MMMM")
            color: Theme.inkMuted
            font.pixelSize: 18
        }
    }

    // ---------- the person and the password, at the bottom ----------

    ColumnLayout {
        id: form
        property real lift: 0
        property real haze: 0

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.1
        spacing: 0
        transform: [
            Translate { y: form.lift },
            Translate { id: formRise }
        ]
        layer.enabled: haze > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 16
            blur: form.haze * 0.5
        }

        Item {
            id: picture
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 84
            implicitHeight: 84

            // The initial on the accent at 16%, ringed in the accent.
            Rectangle {
                anchors.centerIn: parent
                width: 64
                height: 64
                radius: 32
                color: Theme.accentSoft
                border.color: Theme.accent
                border.width: 1

                UiText {
                    anchors.centerIn: parent
                    text: root.displayName.slice(0, 1).toUpperCase()
                    color: Theme.accentText
                    font.pixelSize: 24
                    font.weight: Theme.headingWeight
                }
            }

            // The ring: a sweeping arc while checking, closing into a circle on the right
            // password, flashing red on a wrong one.
            Shape {
                id: ring
                property real sweep: 0     // 0 to 360: how much of the circle is drawn
                property real turn: 0
                property color tint: Theme.accent
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                rotation: turn

                ShapePath {
                    strokeColor: ring.tint
                    strokeWidth: 2.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap

                    PathAngleArc {
                        centerX: 42
                        centerY: 42
                        radiusX: 38
                        radiusY: 38
                        startAngle: -90
                        sweepAngle: ring.sweep
                    }
                }
            }

            // Checking: a quarter of the ring goes round and round.
            SequentialAnimation {
                running: root.busy && !root.welcomed
                loops: Animation.Infinite
                onStarted: {
                    ring.tint = Theme.accent;
                    ring.sweep = 90;
                }
                onStopped: if (!root.welcomed) {
                    ring.sweep = 0;
                    ring.turn = 0;
                }
                NumberAnimation { target: ring; property: "turn"; from: 0; to: 360; duration: 900 }
            }

            SequentialAnimation {
                id: ringFlash
                ScriptAction {
                    script: {
                        ring.turn = 0;
                        ring.tint = Theme.danger;
                        ring.sweep = 360;
                        ring.opacity = 1;
                    }
                }
                PauseAnimation { duration: 380 }
                NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 320 }
                ScriptAction {
                    script: {
                        ring.sweep = 0;
                        ring.opacity = 1;
                        ring.tint = Theme.accent;
                    }
                }
            }
        }

        UiText {
            id: nameText
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.space2
            text: root.displayName
            font.pixelSize: 15
            font.weight: Theme.labelWeight
        }

        // The box, and the lines under it.
        ColumnLayout {
            id: box
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.space4
            spacing: Theme.space2
            transform: Translate { id: nudge }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: nudge; property: "x"; to: -14; duration: 50 }
                NumberAnimation { target: nudge; property: "x"; to: 12; duration: 70 }
                NumberAnimation { target: nudge; property: "x"; to: -8; duration: 60 }
                NumberAnimation { target: nudge; property: "x"; to: 5; duration: 50 }
                NumberAnimation { target: nudge; property: "x"; to: 0; duration: 40 }
            }

            // A 300 x 46 pill, the submit button inside its right end.
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 300
                implicitHeight: 46

                // The focus ring: 2 px in the accent's text colour, 2 px out.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: height / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Theme.accentText
                    visible: field.activeFocus && !(root.messageIsError && root.message)
                }

                Rectangle {
                    id: pillField
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.tint(Theme.panel, 0.7)
                    opacity: root.lockedFor > 0 ? 0.6 : 1
                    border.color: root.messageIsError && root.message ? Theme.danger : Theme.border
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: Theme.durationInstant } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 18
                        anchors.rightMargin: 5
                        spacing: Theme.space2

                        TextInput {
                            id: field

                            Layout.fillWidth: true
                            enabled: !root.busy && !root.welcomed && root.lockedFor === 0
                            echoMode: TextInput.Password
                            passwordCharacter: "●"
                            color: Theme.ink
                            selectionColor: Theme.accentSoft
                            selectedTextColor: Theme.ink
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            clip: true
                            Accessible.role: Accessible.EditableText
                            Accessible.name: root.usePin ? "PIN" : "Password"
                            // A PIN: digits only, and it goes as soon as the fourth is typed.
                            maximumLength: root.usePin ? 4 : 32767
                            validator: RegularExpressionValidator { regularExpression: root.usePin ? /[0-9]*/ : /.*/ }
                            inputMethodHints: root.usePin ? Qt.ImhDigitsOnly : Qt.ImhNone
                            onTextChanged: if (root.usePin && text.length === 4 && enabled) root.submit(text)
                            // Clicked into while the clock is up: the same as a key.
                            onActiveFocusChanged: if (activeFocus) root.lift("")
                            Keys.onReturnPressed: if (text.length && enabled) root.submit(text)
                            Keys.onEnterPressed: if (text.length && enabled) root.submit(text)
                            Keys.onEscapePressed: root.reset()

                            UiText {
                                anchors.fill: parent
                                visible: field.text.length === 0
                                text: root.lockedFor > 0 ? "Try again in " + root.lockedFor + " s" : root.usePin ? "PIN" : "Password"
                                color: Theme.inkFaint
                                font.pixelSize: 15
                            }
                        }

                        Rectangle {
                            visible: !root.usePin // a PIN goes by itself
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: 18
                            color: goMouse.containsMouse && field.text.length ? Qt.lighter(Theme.accentFill, 1.08) : Theme.accentFill
                            opacity: field.text.length && field.enabled ? 1 : 0.45
                            scale: goMouse.pressed ? Theme.grow(0.94) : 1
                            Behavior on opacity { NumberAnimation { duration: Theme.durationInstant } }
                            Behavior on scale { NumberAnimation { duration: Theme.durationInstant } }

                            Accessible.role: Accessible.Button
                            Accessible.name: "Sign in"

                            Glyph {
                                anchors.centerIn: parent
                                name: "go-next-symbolic"
                                tint: Theme.onAccent
                            }

                            MouseArea {
                                id: goMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: if (field.text.length && field.enabled) root.submit(field.text)
                            }
                        }
                    }
                }

                // The lock-out: a thin red bar under the pill, draining.
                Rectangle {
                    id: lockBar
                    property real fraction: 0
                    visible: root.lockedFor > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    width: (parent.width - parent.height) * fraction
                    height: 2
                    radius: 1
                    color: Theme.danger
                }
            }

            UiText {
                id: messageLine
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Theme.space1
                Layout.preferredHeight: 20
                text: root.message || (root.capsLock ? "Caps Lock is on" : "")
                color: root.messageIsError ? Theme.danger : Theme.inkMuted
                font.pixelSize: Theme.hintSize
                NumberAnimation { id: messageFade; target: messageLine; property: "opacity"; from: 0; to: 1; duration: 260 }
            }

            UiText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.showHint && root.hint.length > 0
                text: "Hint: " + root.hint
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            // PIN or password, the other way in.
            UiText {
                Layout.alignment: Qt.AlignHCenter
                visible: root.hasPin && !root.pinResting && root.lockedFor === 0
                text: root.usePin ? "Use my password instead" : "Use my PIN instead"
                color: switchMouse.containsMouse ? Theme.accentText : Theme.inkMuted
                font.pixelSize: Theme.hintSize
                font.underline: switchMouse.containsMouse

                MouseArea {
                    id: switchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.switchToPin(!root.usePin)
                }
            }
        }

        // Others who can sign in.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.space3
            visible: root.users.length > 1
            spacing: Theme.space2

            Repeater {
                model: root.users.length > 1 ? root.users : []

                Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool on: modelData.name === root.user
                    implicitWidth: chipRow.implicitWidth + Theme.space3 * 2
                    implicitHeight: 34
                    radius: 17
                    color: on ? Theme.accentSoft : chipMouse.containsMouse ? Theme.hoverIcon : Theme.tint(Theme.panel, 0.7)
                    border.color: on ? Theme.tint(Theme.accent, 0.6) : Theme.border
                    border.width: 1

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Theme.space2

                        Rectangle {
                            implicitWidth: 22
                            implicitHeight: 22
                            radius: 11
                            color: Theme.accentSoft
                            border.color: Theme.accent
                            border.width: 1

                            UiText {
                                anchors.centerIn: parent
                                text: (chip.modelData.full || chip.modelData.name).slice(0, 1).toUpperCase()
                                color: Theme.accentText
                                font.pixelSize: 11
                                font.weight: Theme.headingWeight
                            }
                        }

                        UiText {
                            text: chip.modelData.full || chip.modelData.name
                            font.weight: Theme.labelWeight
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.pickUser(chip.modelData.name);
                            root.failures = 0;
                            root.showHint = false;
                            root.message = "";
                            field.text = "";
                            field.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // ---------- the right password ----------

    property var whenWelcomed: null

    UiText {
        id: greeting
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.42
        opacity: 0
        text: root.greetingText()
        font.pixelSize: 40
        font.weight: Theme.headingWeight
        font.letterSpacing: -0.8
        transform: Translate { id: greetingRise; y: 24 }
    }

    SequentialAnimation {
        id: welcomeAnimation
        ScriptAction {
            script: {
                ring.turn = 0;
                ring.tint = Theme.accent;
                ring.opacity = 1;
            }
        }
        NumberAnimation { target: ring; property: "sweep"; to: 360; duration: 360; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 160 }
        ParallelAnimation {
            NumberAnimation { target: form; property: "opacity"; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: clockBlock; property: "opacity"; to: 0; duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: formRise; property: "y"; to: -40; duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: glow; property: "spread"; to: 1.8; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: corners; property: "opacity"; to: 0; duration: 300 }
            SequentialAnimation {
                PauseAnimation { duration: 260 }
                ParallelAnimation {
                    NumberAnimation { target: greeting; property: "opacity"; to: 1; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
                    NumberAnimation { target: greetingRise; property: "y"; to: 0; duration: 620; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
                }
            }
        }
        PauseAnimation { duration: 500 }
        ScriptAction {
            script: {
                const done = root.whenWelcomed;
                root.whenWelcomed = null;
                if (done) done();
            }
        }
    }

    // ---------- the corner: the network, and the power menu ----------

    Item {
        id: corners
        anchors.fill: parent

        RowLayout {
            id: cornerButtons
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Theme.space4
            spacing: Theme.space2

            Glyph {
                Layout.margins: Theme.space2
                name: Network.wired ? "network-wired-symbolic" : Network.current ? Network.glyphFor(Network.current) : "network-wireless-offline-symbolic"
                opacity: Network.online ? 0.9 : 0.4
            }

            BarButton {
                visible: root.showPower
                implicitWidth: 36
                implicitHeight: 36
                label: "Power"
                glyph: "system-shutdown-symbolic"
                active: root.powerMenu
                onClicked: root.powerMenu = !root.powerMenu
            }
        }

        Rectangle {
            visible: root.powerMenu
            anchors.right: parent.right
            anchors.bottom: cornerButtons.top
            anchors.margins: Theme.space4
            implicitWidth: powerItems.implicitWidth + 5 * 2
            implicitHeight: powerItems.implicitHeight + 5 * 2
            radius: Theme.radiusCard
            color: Theme.panel
            border.color: Theme.border
            border.width: 1

            ColumnLayout {
                id: powerItems
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                    model: [
                        { name: "Sleep", command: ["systemctl", "suspend"] },
                        { name: "Restart", command: ["systemctl", "reboot"] },
                        { name: "Shut down", command: ["systemctl", "poweroff"] }
                    ]

                    MenuRow {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.minimumWidth: 140
                        text: modelData.name
                        onClicked: {
                            root.powerMenu = false;
                            Quickshell.execDetached(modelData.command);
                        }
                    }
                }
            }
        }
    }
}
