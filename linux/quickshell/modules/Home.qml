// Home: on a screen whose workspace has no windows, the launcher's search and Recent sit on
// the backdrop, ready for typing. The first time it shows in a session it greets the user
// ("Good morning, Sam" and the date) before the search rises in. Any window hides it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property var monitor: Hyprland.monitorFor(modelData)
    readonly property var workspace: monitor ? monitor.activeWorkspace : null
    readonly property bool empty: workspace !== null && Array.from(workspace.toplevels.values).length === 0
    readonly property bool enabled: !ShellSettings.values || ShellSettings.values.showHome !== false
    readonly property bool shown: enabled && empty
    readonly property bool focusedHere: Hyprland.focusedMonitor !== null && monitor !== null && Hyprland.focusedMonitor.name === monitor.name
    readonly property bool takesKeys: shown && focusedHere && !ShellState.launcherOpen && !ShellState.paletteOpen && !ShellState.barBusy && !ShellState.settingsOpen

    visible: shown
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "graphite-home"
    WlrLayershell.keyboardFocus: takesKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // The greeting plays once a session (a reload of the shell does not replay it).
    PersistentProperties {
        id: session
        reloadableId: "home"
        property bool greeted: false
    }

    property bool greeting: false

    // Hidden by a window opening: that window gets the keyboard Home was holding.
    onShownChanged: {
        if (shown) {
            start();
            return;
        }
        const windows = workspace ? Array.from(workspace.toplevels.values) : [];
        const newest = windows[windows.length - 1];
        if (newest && focusedHere) Taskbar.focusWindow(Taskbar.addressOf(newest));
    }
    Component.onCompleted: if (shown) start()
    onTakesKeysChanged: if (takesKeys) view.focusSearch()

    function start() {
        view.reset();
        if (!session.greeted && focusedHere) {
            session.greeted = true;
            greeting = true;
            intro.restart();
        }
    }

    function greetingText() {
        const hour = new Date().getHours();
        const part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";
        const name = view.userName.split(" ")[0];
        return name ? part + ", " + name : part;
    }

    SequentialAnimation {
        id: intro
        ParallelAnimation {
            NumberAnimation { target: hello; property: "opacity"; from: 0; to: 1; duration: 1000; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
            NumberAnimation { target: helloRise; property: "y"; from: 24; to: 0; duration: 1000; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
        }
        PauseAnimation { duration: 400 }
        ScriptAction { script: root.greeting = false }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.16
        width: Math.min(720, parent.width - Theme.space10 * 2)
        height: parent.height * 0.7
        spacing: Theme.space6

        ColumnLayout {
            id: hello
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.space1
            transform: Translate { id: helloRise }

            UiText {
                Layout.alignment: Qt.AlignHCenter
                text: root.greetingText()
                font.pixelSize: Theme.displaySize
                font.weight: Theme.displayWeight
            }

            UiText {
                Layout.alignment: Qt.AlignHCenter
                text: Qt.formatDate(new Date(), "dddd d MMMM")
                color: Theme.inkMuted
            }
        }

        LauncherView {
            id: view

            Layout.fillWidth: true
            Layout.fillHeight: true
            mode: "home"
            opacity: root.greeting ? 0 : 1
            transform: Translate {
                y: root.greeting ? Theme.rise * 2 : 0
                Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter } }
            }
            Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter } }
            // Home never closes: Escape only clears the search; opening something hides it.
            onDone: reset()
        }
    }
}
