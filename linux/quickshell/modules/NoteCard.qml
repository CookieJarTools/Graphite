// One notification in the calendar panel: the app, how long ago, its summary and text. A click
// runs its default action; x dismisses it.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.config
import qs.services

Rectangle {
    id: root

    required property var modelData
    readonly property var notification: modelData.notification

    implicitHeight: lines.implicitHeight + Theme.space3 * 2
    radius: Theme.radiusCard
    color: mouse.containsMouse ? Theme.hoverRow : Theme.cardFill
    border.color: Theme.cardBorder
    border.width: 1
    Behavior on color { ColorAnimation { duration: Theme.durationInstant } }

    function ago(time) {
        const minutes = Math.round((Date.now() - time) / 60000);
        if (minutes < 1) return "now";
        if (minutes < 60) return minutes + " min";
        const hours = Math.round(minutes / 60);
        if (hours < 24) return hours + " h";
        return Qt.formatDate(new Date(time), "d MMM");
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { if (root.notification) Notifs.open(root.notification); }
    }

    ColumnLayout {
        id: lines
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            IconImage {
                implicitSize: 16
                source: root.notification && root.notification.appIcon
                    ? Quickshell.iconPath(root.notification.appIcon, "dialog-information")
                    : Quickshell.iconPath("dialog-information")
            }

            UiText {
                Layout.fillWidth: true
                text: root.notification ? (root.notification.appName || "Notification") : ""
                color: Theme.inkFaint
                font.pixelSize: Theme.sectionSize
                font.weight: Theme.labelWeight
            }

            UiText {
                text: root.ago(root.modelData.time)
                color: Theme.inkFaint
                font.pixelSize: Theme.sectionSize
            }

            BarButton {
                implicitWidth: 22
                implicitHeight: 22
                glyph: "window-close-symbolic"
                label: "Dismiss"
                opacity: mouse.containsMouse ? 1 : 0.5
                onClicked: { if (root.notification) Notifs.dismiss(root.notification); }
            }
        }

        UiText {
            Layout.fillWidth: true
            text: root.notification ? root.notification.summary : ""
            font.weight: Theme.headingWeight
        }

        UiText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.notification ? root.notification.body : ""
            color: Theme.inkMuted
            font.pixelSize: Theme.hintSize
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }
    }
}
