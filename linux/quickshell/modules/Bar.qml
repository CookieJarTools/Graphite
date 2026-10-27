// One screen's bar, floating at the bottom with its strip reserved (windows end above it),
// and the panels that open from it: quick settings and the calendar at its right end, the
// hidden tray icons over the chevron, an app's menu over the app.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.services

Scope {
    id: scope

    required property var modelData
    readonly property string screenName: modelData.name

    PanelWindow {
        id: bar

        screen: scope.modelData
        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: Theme.taskbarHeight + Theme.space2 * 2
        exclusiveZone: implicitHeight
        color: "transparent"
        WlrLayershell.namespace: "graphite-bar"
        // Only the bar itself takes clicks; the strip around it shows the backdrop.
        mask: Region { item: pill }

        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.space2
            width: Math.min(row.implicitWidth + Theme.space2 * 2, parent.width - Theme.space2 * 2)
            height: Theme.taskbarHeight
            radius: Theme.radiusLg
            color: Theme.surface200
            border.color: Theme.glassEdge
            border.width: 1

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: Theme.space1

                BarButton {
                    glyph: "system-search-symbolic"
                    active: ShellState.launcherOpen
                    onClicked: ShellState.toggleLauncher()
                }

                Repeater {
                    model: Apps.items

                    AppButton { screenName: scope.screenName }
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

    AppMenu {
        screen: scope.modelData
        screenName: scope.screenName
        barWindow: bar
    }
}
