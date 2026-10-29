// The Snipping Tool's surfaces (services/Capture.qml). Over the screen under the pointer: the
// still of it, dimmed, with the toolbar at the top (screenshot or record; an area, a window or
// the whole screen; a delay) and the area being dragged out, or the window under the pointer,
// shown clear with its size. Then, while counting down or recording, a small pill at the top:
// the seconds left, or the time recorded and Stop. Escape cancels.
//
//   qs -c graphite ipc call capture screenshot | record | cancel | stop | delay 3 | kind screen
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

Scope {
    id: root

    function screenFor(monitor) {
        const screens = Array.from(Quickshell.screens);
        return screens.find(candidate => monitor && candidate.name === monitor.name) || screens[0];
    }

    GlobalShortcut {
        name: "capture"
        description: "Snipping Tool: take a screenshot (Print, Super+Shift+S)"
        onPressed: Capture.show("screenshot")
    }

    GlobalShortcut {
        name: "capture-record"
        description: "Snipping Tool: record the screen, or stop recording (Super+Shift+R)"
        onPressed: Capture.show("record")
    }

    IpcHandler {
        target: "capture"

        function screenshot(): void { Capture.show("screenshot"); }
        function record(): void { Capture.show("record"); }
        function cancel(): void { Capture.cancel(); }
        function stop(): void { Capture.stop(); }
        function delay(seconds: int): void { Capture.delay = seconds; }
        function kind(name: string): void { Capture.setKind(name); }
        function state(): string { return JSON.stringify({ open: Capture.open, mode: Capture.mode, kind: Capture.kind, delay: Capture.delay, countdown: Capture.countdown, recording: Capture.recording, recorder: Capture.recorder, monitor: Capture.monitor }); }
    }

    // ---------- choosing ----------

    PanelWindow {
        id: overlay

        screen: root.screenFor(Capture.monitor)
        visible: Capture.open
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-capture"
        WlrLayershell.keyboardFocus: Capture.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // The area being dragged out (from where the button went down), or null.
        property var drag: null
        property point pointer: Qt.point(-1, -1)
        readonly property var hovered: Capture.kind === "window" ? Capture.windowAt(pointer.x, pointer.y) : null
        // What would be captured, in this screen's coordinates.
        readonly property var chosen: {
            if (Capture.kind === "rectangle" && drag) return drag;
            if (hovered && Capture.monitor) return { x: hovered.x - Capture.monitor.x, y: hovered.y - Capture.monitor.y, width: hovered.width, height: hovered.height };
            return null;
        }

        onVisibleChanged: {
            drag = null;
            if (visible) keys.forceActiveFocus();
        }

        Image {
            id: still
            anchors.fill: parent
            source: Capture.still
            smooth: true
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
        }

        // The chosen part, clear of the dim.
        Item {
            visible: overlay.chosen !== null
            x: overlay.chosen ? overlay.chosen.x : 0
            y: overlay.chosen ? overlay.chosen.y : 0
            width: overlay.chosen ? overlay.chosen.width : 0
            height: overlay.chosen ? overlay.chosen.height : 0
            clip: true

            Image {
                x: -parent.x
                y: -parent.y
                width: overlay.width
                height: overlay.height
                source: Capture.still
                smooth: true
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.accent
                border.width: 2
            }
        }

        // Its size, by its corner.
        Rectangle {
            visible: overlay.chosen !== null && overlay.chosen.width > 0
            x: overlay.chosen ? Math.min(overlay.width - width - Theme.space2, overlay.chosen.x + overlay.chosen.width - width) : 0
            y: overlay.chosen ? Math.min(overlay.height - height - Theme.space2, overlay.chosen.y + overlay.chosen.height + Theme.space2) : 0
            implicitWidth: sizeText.implicitWidth + Theme.space3 * 2
            implicitHeight: 24
            radius: Theme.radiusSm
            color: Theme.surface200
            border.color: Theme.glassEdge

            UiText {
                id: sizeText
                anchors.centerIn: parent
                text: overlay.chosen ? Math.round(overlay.chosen.width * Capture.monitor.scale) + " × " + Math.round(overlay.chosen.height * Capture.monitor.scale) : ""
                font.family: Theme.fontMono
                font.pixelSize: Theme.identifierSize
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Capture.kind === "rectangle" ? Qt.CrossCursor : Qt.PointingHandCursor
            onPositionChanged: mouse => {
                overlay.pointer = Qt.point(mouse.x, mouse.y);
                if (!overlay.drag || !pressed) return;
                overlay.drag = {
                    x: Math.min(overlay.drag.startX, mouse.x),
                    y: Math.min(overlay.drag.startY, mouse.y),
                    width: Math.abs(mouse.x - overlay.drag.startX),
                    height: Math.abs(mouse.y - overlay.drag.startY),
                    startX: overlay.drag.startX,
                    startY: overlay.drag.startY
                };
            }
            onPressed: mouse => {
                if (Capture.kind === "rectangle") overlay.drag = { x: mouse.x, y: mouse.y, width: 0, height: 0, startX: mouse.x, startY: mouse.y };
            }
            onReleased: mouse => {
                if (Capture.kind === "rectangle") {
                    const area = overlay.drag;
                    overlay.drag = null;
                    if (area && area.width >= 4 && area.height >= 4) Capture.take(area);
                } else if (Capture.kind === "window") {
                    if (overlay.chosen) Capture.take(overlay.chosen);
                } else {
                    Capture.take({ x: 0, y: 0, width: overlay.width, height: overlay.height });
                }
            }
        }

        Item {
            id: keys
            focus: true
            Keys.onEscapePressed: Capture.cancel()
            Keys.onReturnPressed: if (Capture.kind === "screen") Capture.take({ x: 0, y: 0, width: overlay.width, height: overlay.height })
        }

        // ---------- the toolbar ----------

        ColumnLayout {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.space6
            spacing: Theme.space2

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: bar.implicitWidth + Theme.space2 * 2
                implicitHeight: bar.implicitHeight + Theme.space2 * 2
                radius: Theme.radiusMd
                color: Theme.surface200
                border.color: Theme.glassEdge
                border.width: 1

                RowLayout {
                    id: bar
                    anchors.centerIn: parent
                    spacing: Theme.space1

                    ToolChoice { glyph: "camera-photo-symbolic"; text: "Screenshot"; chosen: Capture.mode === "screenshot"; onClicked: Capture.mode = "screenshot" }
                    ToolChoice { glyph: "camera-video-symbolic"; text: "Record"; chosen: Capture.mode === "record"; onClicked: Capture.mode = "record" }

                    Divider {}

                    ToolChoice { glyph: "selection-mode-symbolic"; text: "Rectangle"; chosen: Capture.kind === "rectangle"; onClicked: Capture.setKind("rectangle") }
                    ToolChoice { glyph: "focus-windows-symbolic"; text: "Window"; chosen: Capture.kind === "window"; onClicked: Capture.setKind("window") }
                    ToolChoice { glyph: "view-fullscreen-symbolic"; text: "Full screen"; chosen: false; onClicked: Capture.setKind("screen") }

                    Divider {}

                    ToolChoice { glyph: "timer-symbolic"; text: Capture.delay ? Capture.delay + " s delay" : "No delay"; chosen: Capture.delay > 0; onClicked: Capture.nextDelay() }

                    Divider {}

                    ToolChoice { glyph: "window-close-symbolic"; text: ""; chosen: false; onClicked: Capture.cancel() }
                }
            }

            // What to do next, or what recording needs.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: note.implicitWidth + Theme.space4 * 2
                implicitHeight: note.implicitHeight + Theme.space2 * 2
                radius: Theme.radiusSm
                color: Theme.surface200
                border.color: Theme.glassEdge
                border.width: 1

                RowLayout {
                    id: note
                    anchors.centerIn: parent
                    spacing: Theme.space3

                    UiText {
                        readonly property bool needsRecorder: Capture.mode === "record" && !Capture.recorder
                        text: needsRecorder ? (Capture.installing ? "Installing the screen recorder…" : "Recording needs a screen recorder: wf-recorder, from Arch Linux's own apps")
                            : (Capture.kind === "rectangle" ? "Drag out an area" : Capture.kind === "window" ? "Click a window" : "Click anywhere for the whole screen")
                                + (Capture.delay ? ", then " + Capture.delay + " seconds" : "") + "  ·  Esc to cancel"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.actionSize
                    }

                    PillButton {
                        visible: Capture.mode === "record" && !Capture.recorder && !Capture.installing
                        primary: true
                        text: "Install"
                        onClicked: Capture.installRecorder()
                    }
                }
            }
        }
    }

    // ---------- counting down, recording ----------

    PanelWindow {
        id: pill

        screen: root.screenFor(Capture.monitor)
        visible: Capture.countdown > 0 || Capture.recording
        anchors.top: true
        margins.top: Theme.space2
        implicitWidth: pillBox.implicitWidth
        implicitHeight: pillBox.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-capture-pill"

        property double now: Date.now()
        Timer {
            interval: 500
            repeat: true
            running: Capture.recording
            onTriggered: pill.now = Date.now()
        }

        function elapsed() {
            const seconds = Math.max(0, Math.floor((pill.now - Capture.recordingSince) / 1000));
            const pad = value => (value < 10 ? "0" : "") + value;
            return Math.floor(seconds / 60) + ":" + pad(seconds % 60);
        }

        Rectangle {
            id: pillBox
            implicitWidth: pillRow.implicitWidth + Theme.space3 * 2
            implicitHeight: 40
            radius: Theme.radiusFull
            color: Theme.surface200
            border.color: Theme.glassEdge
            border.width: 1

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.space2

                Rectangle {
                    visible: Capture.recording
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: Theme.danger

                    SequentialAnimation on opacity {
                        running: Capture.recording
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 700 }
                        NumberAnimation { to: 1; duration: 700 }
                    }
                }

                UiText {
                    text: Capture.recording ? pill.elapsed() : (Capture.pending && Capture.pending.mode === "record" ? "Recording in " : "Screenshot in ") + Capture.countdown
                    font.family: Capture.recording ? Theme.fontMono : Theme.fontSans
                    font.pixelSize: Theme.actionSize
                }

                ToolChoice {
                    visible: Capture.recording
                    glyph: "media-playback-stop-symbolic"
                    text: "Stop"
                    chosen: false
                    onClicked: Capture.stop()
                }

                ToolChoice {
                    visible: !Capture.recording
                    glyph: "window-close-symbolic"
                    text: ""
                    chosen: false
                    onClicked: Capture.cancel()
                }
            }
        }
    }

    // A toolbar button: a glyph, and a word unless it's only the glyph; the chosen one in the accent.
    component ToolChoice: Rectangle {
        id: choice

        property string glyph
        property string text
        property bool chosen
        signal clicked()

        implicitWidth: choiceRow.implicitWidth + (text ? Theme.space3 * 2 : Theme.space2 * 2)
        implicitHeight: 32
        radius: Theme.radiusSm
        color: chosen ? Theme.accentSoft : choiceMouse.containsMouse ? Theme.surface300 : "transparent"
        border.color: chosen ? Theme.accent : "transparent"
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

        RowLayout {
            id: choiceRow
            anchors.centerIn: parent
            spacing: Theme.space2

            Glyph {
                name: choice.glyph
                tint: choice.chosen ? Theme.accent : Theme.ink
            }

            UiText {
                visible: choice.text.length > 0
                text: choice.text
                color: choice.chosen ? Theme.accent : Theme.ink
                font.pixelSize: Theme.actionSize
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: choiceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.clicked()
        }
    }

    component Divider: Rectangle {
        implicitWidth: 1
        implicitHeight: 20
        Layout.leftMargin: Theme.space1
        Layout.rightMargin: Theme.space1
        color: Theme.line
    }
}
