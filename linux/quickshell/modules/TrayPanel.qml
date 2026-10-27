// The apps' tray icons (StatusNotifierItem), over the chevron. A click is the app's own
// click; a right click opens its menu; a middle click its second action. The hovered icon's
// name shows underneath.
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
    panelWidth: columns * 38 + Theme.space4 * 2
    property string hovered: ""

    QsMenuAnchor {
        id: menu
        anchor.window: root
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
                radius: Theme.radiusSm
                color: area.containsMouse ? Theme.surface300 : "transparent"

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
                            menu.menu = item.menu;
                            menu.anchor.item = cell;
                            menu.open();
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
        visible: root.count === 0
        text: "No tray icons"
        color: Theme.inkMuted
    }
}
