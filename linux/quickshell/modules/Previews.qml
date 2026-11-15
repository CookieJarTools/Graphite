// Live pictures of a running app's windows (up to four), over its pill after a moment's
// hover; a click brings that window forward. They stay while the pointer is on the pill or
// on them, and go a little after it leaves both (Bar.qml times that).
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.config
import qs.services

PanelWindow {
    id: root

    property var bar: null

    readonly property var item: bar && bar.previewRef !== "" ? Taskbar.items.find(candidate => candidate.ref === bar.previewRef) || null : null
    readonly property var windows: item ? item.windows.slice(0, 4) : []
    readonly property bool open: windows.length > 0

    visible: open
    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: Theme.barTop + Theme.space2
        left: bar ? Math.max(Theme.space2, Math.min(bar.previewX - implicitWidth / 2, screen.width - implicitWidth - Theme.space2)) : 0
    }
    exclusiveZone: 0
    implicitWidth: cards.implicitWidth + Theme.space2 * 2
    implicitHeight: cards.implicitHeight + Theme.space2 * 2
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "graphite-panel"

    HoverHandler {
        onHoveredChanged: {
            if (!root.bar) return;
            root.bar.previewsHovered = hovered;
            if (!hovered) root.bar.hoverChanged("", 0);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLg
        color: Theme.glass(Theme.panel, 0.94)
        border.color: Theme.glassEdge
        border.width: 1

        RowLayout {
            id: cards
            anchors.centerIn: parent
            spacing: Theme.space2

            Repeater {
                model: root.windows

                Rectangle {
                    id: card

                    required property var modelData
                    readonly property var toplevel: Taskbar.toplevelFor(modelData.hwnd)

                    implicitWidth: 220
                    implicitHeight: 156
                    radius: Theme.radiusMd
                    color: mouse.containsMouse ? Theme.surface300 : "transparent"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space2
                        spacing: Theme.space2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            IconImage {
                                implicitSize: 16
                                source: Apps.iconFor(root.item ? root.item.key : "", root.item ? root.item.icon : "")
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: card.modelData.title || "Untitled window"
                                font.pixelSize: Theme.hintSize
                            }

                            Rectangle {
                                visible: !!card.modelData.tag
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: card.modelData.tag ? Taskbar.tagColour(card.modelData.tag.color) : "transparent"
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.radiusSm
                            color: Theme.surface100
                            clip: true

                            ScreencopyView {
                                anchors.fill: parent
                                visible: !card.modelData.minimized
                                captureSource: root.open && !card.modelData.minimized && card.toplevel ? card.toplevel.wayland : null
                                live: true
                                constraintSize: Qt.size(width, height)
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: card.modelData.minimized
                                spacing: Theme.space1

                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitSize: 32
                                    source: Apps.iconFor(root.item ? root.item.key : "", root.item ? root.item.icon : "")
                                }

                                UiText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Minimised"
                                    color: Theme.inkMuted
                                    font.pixelSize: Theme.hintSize
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.bar.previewRef = "";
                            Taskbar.focusWindow(card.modelData.hwnd);
                        }
                    }
                }
            }
        }
    }
}
