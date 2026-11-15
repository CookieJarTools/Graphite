// The shell's menus (ShellState.menu): 220 px cards of 30 px rows with ticks, shortcuts (mono,
// at the right), separators and submenus that open beside their row on hover; destructive rows
// in red. One per screen, over everything; a click outside, Escape, or
// choosing a row closes it. Arrows and Enter work too.
import QtQuick
import QtQuick.Effects
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

    readonly property var menu: ShellState.menu
    readonly property bool open: menu !== null && menu.screen === modelData.name
    property var submenu: null
    property real submenuY: 0
    property int selected: -1

    visible: open
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "graphite-menu"
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        Region { item: main }
        Region { item: side }
    }

    onMenuChanged: {
        submenu = null;
        selected = -1;
        if (open) keys.forceActiveFocus();
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: ShellState.menu = null
    }

    function choose(item) {
        if (!item || item.separator || item.enabled === false) return;
        if (item.submenu) return;
        ShellState.menu = null;
        if (item.action) item.action();
    }

    function rows() {
        return menu ? menu.items.filter(item => item && item.visible !== false) : [];
    }

    function step(delta) {
        const list = rows();
        for (let index = selected + delta, tries = 0; tries < list.length; index += delta, tries++) {
            const wrapped = (index + list.length) % list.length;
            if (!list[wrapped].separator && list[wrapped].enabled !== false) {
                selected = wrapped;
                return;
            }
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            const list = root.rows();
            if (event.key === Qt.Key_Escape) ShellState.menu = null;
            else if (event.key === Qt.Key_Down) root.step(1);
            else if (event.key === Qt.Key_Up) root.step(-1);
            else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && list[root.selected]) {
                if (list[root.selected].submenu) root.submenu = list[root.selected].submenu;
                else root.choose(list[root.selected]);
            } else return;
            event.accepted = true;
        }
    }

    component MenuList: Rectangle {
        id: box

        property var items: []
        property bool isSide: false

        width: Math.max(220, column.implicitWidth + 5 * 2)
        height: column.implicitHeight + 5 * 2
        radius: Theme.radiusCard
        color: Theme.glass(Theme.panel, 0.94)
        border.color: Theme.border
        border.width: 1

        RectangularShadow {
            z: -1
            anchors.fill: parent
            offset.y: 12
            blur: 32
            spread: -6
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.16)
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 5
            spacing: 0

            Repeater {
                model: box.items.filter(item => item && item.visible !== false)

                Item {
                    id: row

                    required property var modelData
                    required property int index
                    readonly property bool highlighted: (mouse.containsMouse || (!box.isSide && root.selected === index)) && modelData.enabled !== false

                    Layout.fillWidth: true
                    implicitWidth: line.implicitWidth + Theme.space3 * 2
                    implicitHeight: modelData.separator ? 9 : 30

                    // 1 px, with 4 px above and below.
                    Rectangle {
                        visible: row.modelData.separator === true
                        anchors.verticalCenter: parent.verticalCenter
                        x: -5
                        width: parent.width + 10
                        height: 1
                        color: Theme.divider
                    }

                    Rectangle {
                        visible: !row.modelData.separator
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: row.highlighted || (!box.isSide && root.submenu !== null && root.submenu === row.modelData.submenu) ? (row.modelData.danger ? Theme.tint(Theme.danger, 0.12) : Theme.hoverIcon) : "transparent"

                        RowLayout {
                            id: line
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space2

                            Item {
                                implicitWidth: 16
                                implicitHeight: 16
                                visible: box.items.some(item => item && item.checked !== undefined) || row.modelData.colour !== undefined

                                Glyph {
                                    anchors.centerIn: parent
                                    visible: row.modelData.checked === true
                                    name: "object-select-symbolic"
                                    implicitSize: 14
                                    tint: Theme.accentText
                                }

                                Rectangle {
                                    anchors.centerIn: parent
                                    visible: row.modelData.colour !== undefined && row.modelData.checked !== true
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: row.modelData.colour || "transparent"
                                }
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: row.modelData.text || ""
                                color: row.modelData.danger ? Theme.danger : Theme.ink
                                opacity: row.modelData.enabled === false ? 0.4 : 1
                            }

                            UiText {
                                visible: !!row.modelData.hint
                                text: row.modelData.hint || ""
                                color: Theme.inkFaint
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.sectionSize
                            }

                            Glyph {
                                visible: !!row.modelData.submenu
                                name: "go-next-symbolic"
                                implicitSize: 14
                                tint: Theme.inkFaint
                            }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !row.modelData.separator && row.modelData.enabled !== false
                        onEntered: {
                            if (box.isSide) return;
                            root.selected = row.index;
                            if (row.modelData.submenu) {
                                root.submenu = row.modelData.submenu;
                                root.submenuY = box.y + row.y;
                            } else {
                                root.submenu = null;
                            }
                        }
                        onClicked: {
                            if (row.modelData.submenu) {
                                root.submenu = row.modelData.submenu;
                                root.submenuY = box.y + row.y;
                            } else {
                                root.choose(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    MenuList {
        id: main
        items: root.menu ? root.menu.items : []
        x: root.menu ? Math.max(Theme.space2, Math.min(root.menu.x, root.width - width - Theme.space2)) : 0
        y: root.menu ? Math.max(Theme.space2, Math.min(root.menu.above ? root.menu.y - height : root.menu.y, root.height - height - Theme.space2)) : 0
    }

    // Beside its row: to the right when there is room, else to the left.
    MenuList {
        id: side
        isSide: true
        visible: root.submenu !== null
        items: root.submenu || []
        x: main.x + main.width + width + 4 <= root.width ? main.x + main.width + 4 : main.x - width - 4
        // Off the screen while closed, so its part of the window's input region is nowhere.
        y: visible ? Math.max(Theme.space2, Math.min(root.submenuY - Theme.space1, root.height - height - Theme.space2)) : -10000
    }
}
