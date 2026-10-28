// One notification pop-up: the app, x, the summary and text, and its actions. It leaves after
// a few seconds unless the pointer is on it or it is critical; it stays in the calendar.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services

Rectangle {
    id: root

    required property var modelData
    readonly property var notification: modelData.notification
    property bool fresh: false

    implicitHeight: lines.implicitHeight + Theme.space3 * 2
    radius: Theme.radiusMd
    color: Theme.surface200
    border.color: Theme.glassEdge
    border.width: 1

    // In from the right; out to the right, then gone (hidden, or dismissed for good).
    transform: Translate { id: slide }
    Component.onCompleted: if (fresh) arrive.start()

    ParallelAnimation {
        id: arrive
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
        NumberAnimation { target: slide; property: "x"; from: 32; to: 0; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
    }

    property bool dismissing: false
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
            NumberAnimation { target: slide; property: "x"; to: 32; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeExit }
        }
        ScriptAction {
            script: {
                if (!root.notification) return;
                if (root.dismissing) Notifs.dismiss(root.notification);
                else Notifs.hidePopup(root.notification);
            }
        }
    }

    function goAway(dismiss) {
        dismissing = dismiss;
        leave.start();
    }

    Timer {
        interval: Notifs.popupMilliseconds
        running: !mouse.containsMouse && root.notification !== null && root.notification.urgency !== NotificationUrgency.Critical
        onTriggered: root.goAway(false)
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
        spacing: Theme.space1

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
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            BarButton {
                implicitWidth: 20
                implicitHeight: 20
                glyph: "window-close-symbolic"
                onClicked: root.goAway(true)
            }
        }

        UiText {
            Layout.fillWidth: true
            text: root.notification ? root.notification.summary : ""
            font.weight: Font.DemiBold
            color: root.notification && root.notification.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.ink
        }

        UiText {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.notification ? root.notification.body : ""
            color: Theme.inkMuted
            wrapMode: Text.Wrap
            maximumLineCount: 4
        }

        RowLayout {
            Layout.fillWidth: true
            visible: actionRepeater.count > 0
            spacing: Theme.space2

            Repeater {
                id: actionRepeater

                model: root.notification
                    ? Array.from(root.notification.actions).filter(action => action.identifier !== "default").slice(0, 2)
                    : []

                MenuRow {
                    required property var modelData
                    text: modelData.text
                    color: Theme.surface100
                    onClicked: modelData.invoke()
                }
            }
        }
    }
}
