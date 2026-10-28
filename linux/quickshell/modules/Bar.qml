// One screen's bar, floating at the bottom, and what opens from it: quick settings and the
// calendar at its right end, the tray icons over the chevron, a pill's window list or folder,
// window previews, the tag panel. Its strip is kept clear of windows unless it auto-hides
// (always, or while the focused window is maximised); then it slides away and comes back
// when the pointer touches the bottom edge.
//
// One pointer area covers the pills: a click starts or brings forward, a pill with several
// windows (or a folder) opens its list, a right click its menu, a middle click a new window;
// hovering a running app shows its windows; dragging moves a pill, and holding it over the
// middle of another for half a second makes a folder of the two.
import QtQuick
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
    property bool revealed: false
    readonly property bool inUse: (ShellState.barBusy && (ShellState.panelScreen === screenName || (ShellState.popover && ShellState.popover.screen === screenName)
        || (ShellState.menu && ShellState.menu.screen === screenName) || (ShellState.tagPanel && ShellState.tagPanel.screen === screenName)))
        || previewRef !== "" || dragRef !== ""
    readonly property bool shown: !autoHide || revealed || inUse

    onShownChanged: if (!shown) ShellState.closePanels()

    // Brought back by the edge, it goes again once the pointer is not on it.
    Timer {
        id: hideAgain
        interval: 800
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
        implicitHeight: Theme.taskbarHeight + Theme.space2 * 2
        exclusiveZone: scope.autoHide ? 0 : implicitHeight
        color: "transparent"
        WlrLayershell.namespace: "graphite-bar"
        WlrLayershell.layer: WlrLayer.Top
        // Only the bar itself takes the pointer; the strip around it shows the backdrop.
        mask: Region { item: pill }

        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - Theme.space2 + (scope.shown ? 0 : height + Theme.space2 * 2)
            Behavior on y {
                NumberAnimation {
                    duration: Theme.durationFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: scope.shown ? Theme.easeEnter : Theme.easeExit
                }
            }
            width: Math.min(row.implicitWidth + Theme.space2 * 2, parent.width - Theme.space2 * 2)
            height: Theme.taskbarHeight
            radius: Theme.radiusLg
            color: Theme.surface200
            border.color: Theme.glassEdge
            border.width: 1

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
                    glyph: "system-search-symbolic"
                    active: ShellState.launcherOpen
                    onClicked: ShellState.toggleLauncher()
                }

                Item {
                    id: apps
                    implicitWidth: pills.implicitWidth
                    implicitHeight: 36
                    visible: scope.shownItems.length > 0

                    Row {
                        id: pills
                        spacing: Theme.space1

                        Repeater {
                            id: repeater
                            model: scope.shownItems

                            TaskButton {
                                hovered: scope.hoverRef === modelData.ref && scope.dragRef === ""
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
                        width: 44
                        height: 44
                        radius: Theme.radiusMd
                        color: Theme.surface300
                        border.color: Theme.glassEdge
                        border.width: 1
                        opacity: 0.92

                        Glyph {
                            anchors.centerIn: parent
                            implicitSize: 24
                            readonly property var item: scope.itemByRef(scope.dragRef)
                            source: item ? (item.type === "folder" ? Quickshell.iconPath("folder", "folder") : Apps.iconFor(item.key, item.icon)) : ""
                        }
                    }
                }

                Rectangle {
                    Layout.leftMargin: Theme.space1
                    Layout.rightMargin: Theme.space1
                    implicitWidth: 1
                    implicitHeight: 24
                    color: Theme.line
                }

                BarButton {
                    id: chevron
                    glyph: "pan-up-symbolic"
                    active: ShellState.panel === "tray" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("tray", scope.screenName)
                }

                StatusButton {
                    active: ShellState.panel === "quick" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("quick", scope.screenName)
                }

                Clock {
                    active: ShellState.panel === "calendar" && ShellState.panelScreen === scope.screenName
                    onClicked: ShellState.togglePanel("calendar", scope.screenName)
                }
            }
        }
    }

    // While the bar auto-hides: the screen's bottom edge, which brings it back when touched
    // (and keeps it while the pointer rests there).
    PanelWindow {
        screen: scope.modelData
        visible: scope.autoHide
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: 2
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "graphite-bar-edge"

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
        return { screen: screenName, x: x, y: modelData.height - bar.implicitHeight + Theme.space2 - Theme.space1, above: true };
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
