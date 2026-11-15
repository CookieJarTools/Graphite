// One screen's bar, a pill floating 14 px over the bottom edge, and what opens from it: quick
// settings and the calendar at its right end, the tray icons over the chevron, a pill's window
// list or folder, window previews, the tag panel. Its strip is kept clear of windows unless it
// auto-hides (always, or while the focused window is maximised); then, a few seconds after
// the shell starts, it slides down and fades, leaving a small handle at the edge, and comes
// back when the pointer touches the bottom edge.
//
// One pointer area covers the pills: a click starts or brings forward, a pill with several
// windows (or a folder) opens its list, a right click its menu, a middle click a new window;
// hovering a running app shows its windows; dragging moves a pill, and holding it over the
// middle of another for half a second makes a folder of the two.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.config
import qs.services

Scope {
    id: scope

    required property var modelData
    readonly property string screenName: modelData.name

    // ---------- hiding ----------

    readonly property var taskbar: ShellSettings.taskbar || {}
    readonly property bool maximisedHere: {
        const active = Hyprland.activeToplevel;
        if (!active || !active.lastIpcObject || !active.monitor || active.monitor.name !== screenName) return false;
        const workspace = active.lastIpcObject.workspace;
        return active.lastIpcObject.fullscreen > 0 && !(workspace && String(workspace.name).startsWith("special:"));
    }
    // An empty workspace has nothing the bar would be in the way of: it stays.
    readonly property var workspaceHere: {
        const monitor = Hyprland.monitorFor(modelData);
        return monitor ? monitor.activeWorkspace : null;
    }
    readonly property bool emptyHere: workspaceHere !== null && Array.from(workspaceHere.toplevels.values).length === 0
    readonly property bool autoHide: !emptyHere && (!!taskbar.alwaysAutoHide || (!!taskbar.autoHideWhenMaximised && maximisedHere))
    // Shown for a moment when the shell starts, so it can be found, then hidden if it auto-hides.
    property bool revealed: true
    Timer {
        interval: 3200
        running: true
        onTriggered: if (!pillHover.hovered && !edgeMouse.containsMouse) scope.revealed = false
    }
    readonly property bool inUse: ShellState.launcherOpen || (ShellState.barBusy && (ShellState.panelScreen === screenName || (ShellState.popover && ShellState.popover.screen === screenName)
        || (ShellState.menu && ShellState.menu.screen === screenName) || (ShellState.tagPanel && ShellState.tagPanel.screen === screenName)))
        || (Menus.trayAt !== null && Menus.trayAt.screen === screenName) || previewRef !== "" || dragRef !== ""
    readonly property bool shown: !autoHide || revealed || inUse

    onShownChanged: if (!shown) ShellState.closePanels()

    // Brought back by the edge, it goes again once the pointer is not on it.
    Timer {
        id: hideAgain
        interval: 700
        onTriggered: {
            if (pillHover.hovered || edgeMouse.containsMouse) return;
            scope.revealed = false;
        }
    }

    // ---------- previews ----------

    property string previewRef: ""
    property real previewX: 0
    property bool previewsHovered: false
    property string hoverRef: ""

    Timer {
        id: showPreviews
        onTriggered: {
            const item = scope.itemByRef(scope.hoverRef);
            if (!item || item.type !== "app" || !item.running || ShellState.popover || scope.dragRef) return;
            scope.previewRef = scope.hoverRef;
            scope.previewX = scope.hoverX;
        }
    }

    Timer {
        id: closePreviews
        interval: 600
        onTriggered: {
            if (scope.previewsHovered || (scope.hoverRef !== "" && scope.hoverRef === scope.previewRef)) return;
            scope.previewRef = "";
        }
    }

    property real hoverX: 0

    function hoverChanged(ref, x) {
        if (ref === hoverRef) return;
        hoverRef = ref;
        hoverX = x;
        if (ref === "") {
            showPreviews.stop();
            closePreviews.restart();
            return;
        }
        if (previewRef !== "" && ref !== previewRef) {
            const item = itemByRef(ref);
            if (!item || item.type !== "app" || !item.running) {
                closePreviews.restart();
                return;
            }
        }
        showPreviews.interval = previewRef !== "" ? 80 : 450;
        showPreviews.restart();
    }

    // ---------- dragging ----------

    property string dragRef: ""
    property var dragOrder: null   // refs, while dragging
    property string mergeRef: ""
    property string mergeCandidate: ""
    property real ghostX: 0

    readonly property var shownItems: {
        const items = Taskbar.items;
        if (!dragOrder) return items;
        const byRef = {};
        for (const item of items) byRef[item.ref] = item;
        return dragOrder.map(ref => byRef[ref]).filter(Boolean);
    }

    function itemByRef(ref) {
        return Taskbar.items.find(item => item.ref === ref) || null;
    }

    Timer {
        id: mergeHold
        interval: 500
        onTriggered: scope.mergeRef = scope.mergeCandidate
    }

    // Pills seen before do not grow in again when the bar is rebuilt.
    property var seenRefs: ({})

    // ---------- the bar ----------

    PanelWindow {
        id: bar

        screen: scope.modelData
        anchors {
            bottom: true
            left: true
            right: true
        }
        // Room above the pill for its shadow; only the pill takes the pointer (mask, below).
        implicitHeight: Theme.barTop + shadowRoom
        readonly property real shadowRoom: 32
        exclusiveZone: scope.autoHide ? 0 : Theme.barTop
        color: "transparent"
        WlrLayershell.namespace: "graphite-bar"
        WlrLayershell.layer: WlrLayer.Top
        // Only the bar itself takes the pointer; the strip around it shows the backdrop.
        mask: Region { item: pill }

        RectangularShadow {
            anchors.fill: pill
            opacity: pill.opacity
            offset.y: 16
            blur: 40
            spread: -8
            radius: pill.radius
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.5 : 0.18)
        }

        // Hiding: down 84 px and faded out; back the same way. The pill itself moves (not
        // something around it), so the input region (mask) follows it.
        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - Theme.barInset + (scope.shown ? 0 : Theme.move(84))
            Behavior on y { NumberAnimation { duration: Theme.durationBarMove; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            opacity: scope.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durationBarFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
            width: Math.min(row.implicitWidth + Theme.barPadding * 2, parent.width - Theme.space4 * 2)
            height: Theme.taskbarHeight
            radius: Theme.radiusBar
            color: Theme.glass(Theme.panel, 0.82)
            border.color: Theme.border
            border.width: 1

            // The light catching its top edge.
            Rectangle {
                x: pill.radius
                y: 1
                width: pill.width - pill.radius * 2
                height: 1
                color: Theme.sheen
            }

            HoverHandler {
                id: pillHover
                onHoveredChanged: {
                    if (hovered) hideAgain.stop();
                    else if (scope.autoHide) hideAgain.restart();
                }
            }

            // A right click on the bar's empty part: its own menu.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: event => Menus.open(scope.at(event.x + pill.x), Menus.barItems())
            }

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: Theme.space1

                BarButton {
                    implicitWidth: Theme.barButton
                    implicitHeight: Theme.barButton
                    glyph: "view-app-grid-symbolic"
                    label: "Launcher"
                    active: ShellState.launcherOpen
                    onClicked: ShellState.toggleLauncher()
                }

                // The dividers: 1 x 24 px hairlines.
                Rectangle {
                    visible: apps.visible
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitWidth: 1
                    implicitHeight: 24
                    color: Theme.border
                }

                Item {
                    id: apps
                    implicitWidth: pills.implicitWidth
                    implicitHeight: Theme.barButton
                    visible: scope.shownItems.length > 0

                    Row {
                        id: pills
                        spacing: Theme.space1

                        Repeater {
                            id: repeater
                            model: scope.shownItems

                            TaskButton {
                                hovered: scope.hoverRef === modelData.ref && scope.dragRef === ""
                                pressed: pointer.pressed && pointer.pressRef === modelData.ref && scope.dragRef === ""
                                lifted: scope.dragRef === modelData.ref
                                mergeTarget: scope.mergeRef === modelData.ref
                                fresh: {
                                    const seen = scope.seenRefs[modelData.ref] === true;
                                    scope.seenRefs[modelData.ref] = true;
                                    return !seen;
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: pointer

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        property real pressX: 0
                        property string pressRef: ""

                        function pillAt(x) {
                            for (let index = 0; index < repeater.count; index++) {
                                const button = repeater.itemAt(index);
                                if (button && x >= button.x && x < button.x + button.width) return button;
                            }
                            return null;
                        }

                        function centreOf(button) {
                            return pill.x + row.x + apps.x + button.x + button.width / 2;
                        }

                        onPositionChanged: event => {
                            const button = pillAt(event.x);
                            if (scope.dragRef === "") {
                                scope.hoverChanged(button ? button.item.ref : "", button ? centreOf(button) : 0);
                                if (pressed && pressRef !== "" && Math.abs(event.x - pressX) > 5 && (event.buttons & Qt.LeftButton)) {
                                    scope.dragRef = pressRef;
                                    scope.dragOrder = Taskbar.items.map(item => item.ref);
                                    scope.previewRef = "";
                                    ShellState.closePanels();
                                }
                                return;
                            }
                            scope.ghostX = pill.x + row.x + apps.x + event.x;
                            if (!button || button.item.ref === scope.dragRef) {
                                mergeHold.stop();
                                scope.mergeCandidate = "";
                                scope.mergeRef = "";
                                return;
                            }
                            // The middle half of another pill: hold to make a folder. Its outer
                            // quarters: move past it.
                            const within = (event.x - button.x) / button.width;
                            if (within > 0.25 && within < 0.75) {
                                if (scope.mergeCandidate !== button.item.ref) {
                                    scope.mergeCandidate = button.item.ref;
                                    scope.mergeRef = "";
                                    mergeHold.restart();
                                }
                                return;
                            }
                            mergeHold.stop();
                            scope.mergeCandidate = "";
                            scope.mergeRef = "";
                            const order = scope.dragOrder.filter(ref => ref !== scope.dragRef);
                            const target = order.indexOf(button.item.ref);
                            order.splice(within >= 0.75 ? target + 1 : target, 0, scope.dragRef);
                            if (order.join("\n") !== scope.dragOrder.join("\n")) scope.dragOrder = order;
                        }

                        onPressed: event => {
                            const button = pillAt(event.x);
                            pressX = event.x;
                            pressRef = button ? button.item.ref : "";
                        }

                        onReleased: event => {
                            if (scope.dragRef !== "") {
                                const source = scope.dragRef;
                                const target = scope.mergeRef;
                                const order = scope.dragOrder;
                                scope.dragRef = "";
                                scope.dragOrder = null;
                                scope.mergeRef = "";
                                scope.mergeCandidate = "";
                                mergeHold.stop();
                                if (target) {
                                    const result = Taskbar.merge(source, target);
                                    if (result && result.created) scope.openFolder("folder:" + result.id, true);
                                } else {
                                    Taskbar.reorder(order);
                                }
                                return;
                            }
                            const button = pillAt(event.x);
                            if (!button || button.item.ref !== pressRef) return;
                            scope.press(button.item, event.button, centreOf(button));
                        }

                        onExited: if (scope.dragRef === "") scope.hoverChanged("", 0)
                    }

                    // The dragged pill, under the pointer.
                    Rectangle {
                        visible: scope.dragRef !== ""
                        x: scope.ghostX - pill.x - row.x - apps.x - width / 2
                        y: -4
                        width: Theme.barButton
                        height: Theme.barButton
                        radius: Theme.radiusCard
                        color: Theme.raised
                        border.color: Theme.border
                        border.width: 1
                        opacity: 0.92

                        Glyph {
                            anchors.centerIn: parent
                            implicitSize: 20
                            readonly property var item: scope.itemByRef(scope.dragRef)
                            source: item ? (item.type === "folder" ? Quickshell.iconPath("folder", "folder") : Apps.iconFor(item.key, item.icon)) : ""
                        }
                    }
                }

                Rectangle {
                    Layout.leftMargin: 2
                    Layout.rightMargin: 2
                    implicitWidth: 1
                    implicitHeight: 24
                    color: Theme.border
                }

                BarButton {
                    id: chevron
                    implicitWidth: Theme.barButton
                    implicitHeight: Theme.barButton
                    glyph: "pan-up-symbolic"
                    label: "Show hidden icons"
                    active: ShellState.panel === "tray" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("tray", scope.screenName)
                }

                StatusButton {
                    active: ShellState.panel === "quick" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("quick", scope.screenName)
                }

                // Notifications live in the calendar panel, with the month.
                BarButton {
                    implicitWidth: Theme.barButton
                    implicitHeight: Theme.barButton
                    glyph: "notifications-symbolic"
                    label: "Notifications"
                    active: ShellState.panel === "calendar" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("calendar", scope.screenName)

                    Rectangle {
                        visible: Notifs.unseen
                        x: parent.width / 2 + 4
                        y: 11
                        width: 7
                        height: 7
                        radius: 3.5
                        color: Theme.accent
                        border.color: Theme.panel
                        border.width: 1.5
                    }
                }

                Clock {
                    active: ShellState.panel === "calendar" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("calendar", scope.screenName)
                }

                BarButton {
                    implicitWidth: Theme.barButton
                    implicitHeight: Theme.barButton
                    glyph: "system-lock-screen-symbolic"
                    label: "Lock"
                    onClicked: {
                        ShellState.closePanels();
                        ShellState.locked = true;
                    }
                }
            }
        }
    }

    // While the bar auto-hides: the screen's bottom edge, which brings it back when touched
    // (and keeps it while the pointer rests there), with a handle in the middle while hidden.
    // A few pixels only: it takes the clicks meant for windows beneath it.
    PanelWindow {
        screen: scope.modelData
        visible: scope.autoHide
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 4
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-bar-edge"

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 56
            height: 4
            radius: 2
            color: Theme.handle
            opacity: scope.shown ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.durationBarFade } }
        }

        MouseArea {
            id: edgeMouse
            anchors.fill: parent
            hoverEnabled: true
            onEntered: {
                scope.revealed = true;
                hideAgain.restart();
            }
            onExited: hideAgain.restart()
        }
    }

    // Where a menu opens over the bar, at x along it.
    function at(x) {
        return { screen: screenName, x: x, y: modelData.height - Theme.barTop - Theme.space2, above: true };
    }

    function openFolder(ref, rename) {
        const item = itemByRef(ref);
        const button = Array.from({ length: repeater.count }, (_, index) => repeater.itemAt(index)).find(candidate => candidate && candidate.item.ref === ref);
        const x = button ? pill.x + row.x + apps.x + button.x + button.width / 2 : modelData.width / 2;
        ShellState.openPopover(screenName, ref, x);
        if (rename && item) ShellState.renaming = item.id;
        else if (rename) ShellState.renaming = ref.slice("folder:".length);
    }

    // A pill pressed with a mouse button.
    function press(item, button, x) {
        previewRef = "";
        if (button === Qt.RightButton) {
            Menus.open(at(x - 100), item.type === "folder" ? Menus.folderItems(item) : Menus.appItems(item, at(x - 100), null));
            return;
        }
        if (button === Qt.MiddleButton) {
            if (item.type === "app") Apps.launchKey(item.key);
            return;
        }
        if (item.type === "folder" || item.windows.length > 1) {
            if (ShellState.popover && ShellState.popover.ref === item.ref) ShellState.popover = null;
            else ShellState.openPopover(screenName, item.ref, x);
            return;
        }
        ShellState.closePanels();
        Taskbar.activate(item);
    }

    // ---------- what opens from it ----------

    // From the window's right edge to the bar's: the panels line up with the bar's end.
    readonly property real barRightInset: (bar.width - pill.width) / 2

    QuickSettings {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
        rightInset: scope.barRightInset
    }

    CalendarPanel {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
        rightInset: scope.barRightInset
    }

    TrayPanel {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
        centreX: pill.x + row.x + chevron.x + chevron.width / 2
    }

    Popover {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
        bar: scope
    }

    Previews {
        screen: scope.modelData
        bar: scope
    }

    TagPanel {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
    }
}
