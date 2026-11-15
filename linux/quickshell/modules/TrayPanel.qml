// The apps' tray icons (StatusNotifierItem), over the chevron. A click is the app's own
// click; a right click opens its menu (in the shell's own menu, once the panel has gone); a
// middle click its second action. The hovered icon's name shows underneath.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.config
import qs.services

PanelFrame {
    id: root

    name: "tray"
    readonly property int count: SystemTray.items.values.length
    readonly property int columns: Math.max(1, Math.min(5, count))
    // Wide enough for the icons, or for "No tray icons" when there are none.
    panelWidth: (count === 0 ? emptyText.implicitWidth : columns * 38) + Theme.space4 * 2
    property string hovered: ""

    // Where a menu opens: over the clicked icon's column, above the panel.
    function menuAt(cell) {
        const point = cell.mapToItem(null, 0, 0);
        const top = root.screen.height - root.margins.bottom - root.implicitHeight;
        return { screen: root.screenName, x: root.margins.left + point.x, y: top - Theme.space2, above: true };
    }

    // A right click's menu waits until the panel's window has gone: going after the menu had
    // opened, it would close the menu too. Menus holds the bar up meanwhile.
    property var menuFor: null
    onOpenChanged: if (open) menuFor = null
    onVisibleChanged: {
        if (visible || !menuFor) return;
        Menus.openTrayMenu(menuFor.item, menuFor.at);
        menuFor = null;
    }

    GridLayout {
        visible: root.count > 0
        columns: root.columns
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: SystemTray.items

            Rectangle {
                id: cell

                required property var modelData
                implicitWidth: 36
                implicitHeight: 36
                radius: Theme.radiusRow
                color: area.containsMouse ? Theme.hoverIcon : "transparent"

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 18
                    source: cell.modelData.icon
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onContainsMouseChanged: {
                        if (containsMouse) root.hovered = cell.modelData.tooltipTitle || cell.modelData.title || cell.modelData.id;
                        else if (root.hovered) root.hovered = "";
                    }
                    onClicked: event => {
                        const item = cell.modelData;
                        if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && item.onlyMenu)) {
                            if (!item.hasMenu) return;
                            root.menuFor = { item: item, at: root.menuAt(cell) };
                            Menus.holdTrayMenu(root.menuFor.at);
                            ShellState.closePanels();
                        } else if (event.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                        } else {
                            item.activate();
                        }
                    }
                }
            }
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.count > 0
        text: root.hovered
        color: Theme.inkMuted
        font.pixelSize: Theme.hintSize
    }

    UiText {
        id: emptyText
        visible: root.count === 0
        text: "No tray icons"
        color: Theme.inkMuted
    }
}
