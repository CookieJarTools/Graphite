// One notification pop-up: a chip with the app's icon (tinted by how urgent it is), the
// summary and text, the app's name, x, and its actions (the first filled, the second outlined).
// A thin accent bar along the bottom runs down while it waits; it leaves after a few seconds
// unless the pointer is on it (then it starts again) or it is critical; it stays in the
// calendar. Clicking it leads to where it came from (Notifs.open).
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import qs.config
import qs.services

Item {
    id: root

    required property var modelData
    readonly property var notification: modelData.notification
    property bool fresh: false
    // The stack's gap, taken back as this one closes up when it goes.
    property real gap: 0

    readonly property bool critical: !!notification && notification.urgency === NotificationUrgency.Critical
    readonly property bool warning: !critical && !!notification && /warning/.test(notification.appIcon || "")
    readonly property color chipColour: critical ? Theme.danger : warning ? Theme.warning : Theme.accent

    // 1 while shown; down to 0 as it closes up on leaving.
    property real collapse: 1
    // Its full width from the start: made without one, it wrapped its text into a tall column
    // for a moment.
    implicitWidth: Theme.toastWidth
    implicitHeight: card.implicitHeight * collapse
    Layout.bottomMargin: -gap * (1 - collapse)

    Accessible.role: Accessible.Notification
    Accessible.name: notification ? (notification.summary + ". " + notification.body) : ""

    // In from the right, growing from 98%; out to the right, then the stack closes up.
    Component.onCompleted: if (fresh) arrive.start()

    ParallelAnimation {
        id: arrive
        NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.durationToastIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeToast }
        NumberAnimation { target: slide; property: "x"; from: Theme.slide; to: 0; duration: Theme.durationToastIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeToast }
        NumberAnimation { target: card; property: "scale"; from: Theme.grow(0.98); to: 1; duration: Theme.durationToastIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeToast }
    }

    property bool dismissing: false
    SequentialAnimation {
        id: leave
        ParallelAnimation {
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: Theme.durationToastOut * 0.55; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
            NumberAnimation { target: slide; property: "x"; to: Theme.slide; duration: Theme.durationToastOut * 0.55; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
        }
        NumberAnimation { target: root; property: "collapse"; to: 0; duration: Theme.durationToastOut * 0.45; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
        ScriptAction {
            script: {
                if (!root.notification) return;
                if (root.dismissing) Notifs.dismiss(root.notification);
                else Notifs.hidePopup(root.notification);
            }
        }
    }

    function goAway(dismiss) {
        if (leave.running) return;
        dismissing = dismiss;
        countdown.stop();
        leave.start();
    }

    // The wait, shown by the bar along the bottom: 1 down to 0; back to the start while the
    // pointer is on the card. Critical ones wait for a click.
    property real remaining: 1
    readonly property bool waiting: !mouse.containsMouse && root.notification !== null && !root.critical && !leave.running
    onWaitingChanged: if (!waiting && !leave.running) remaining = 1
    NumberAnimation {
        id: countdown
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: Notifs.popupMilliseconds
        running: root.waiting
        onFinished: if (root.remaining <= 0.001) root.goAway(false)
    }

    RectangularShadow {
        anchors.fill: card
        opacity: card.opacity
        offset.y: 12
        blur: 32
        spread: -6
        radius: card.radius
        color: Qt.rgba(0, 0, 0, Theme.dark ? 0.45 : 0.16)
        transform: Translate { x: slide.x }
        visible: root.collapse > 0.5
    }

    Rectangle {
        id: card

        width: parent.width
        implicitHeight: lines.implicitHeight + Theme.space3 * 2
        radius: Theme.radiusMd
        color: Theme.glass(Theme.raised, 0.92)
        border.color: Theme.border
        border.width: 1
        clip: true
        transform: Translate { id: slide }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (root.notification) Notifs.open(root.notification); }
        }

        RowLayout {
            id: lines

            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space3

            // The chip: the app's icon on its colour at 16%.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 28
                implicitHeight: 28
                radius: Theme.radiusControl
                color: Theme.tint(root.chipColour, 0.16)

                readonly property bool appIcon: !root.critical && !root.warning && !!root.notification && !!root.notification.appIcon

                IconImage {
                    visible: parent.appIcon
                    anchors.centerIn: parent
                    implicitSize: 16
                    source: parent.appIcon ? Quickshell.iconPath(root.notification.appIcon, "dialog-information") : ""
                }

                Glyph {
                    visible: !parent.appIcon
                    anchors.centerIn: parent
                    implicitSize: 16
                    name: root.critical ? "dialog-error-symbolic" : root.warning ? "dialog-warning-symbolic" : "dialog-information-symbolic"
                    tint: root.chipColour
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space2

                    UiText {
                        Layout.fillWidth: true
                        text: root.notification ? root.notification.summary : ""
                        font.pixelSize: Theme.bodySize
                        font.weight: Theme.headingWeight
                        color: Theme.ink
                    }

                    UiText {
                        Layout.maximumWidth: 110
                        text: root.notification ? (root.notification.appName || "") : ""
                        color: Theme.inkFaint
                        font.pixelSize: Theme.sectionSize
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.notification ? root.notification.body : ""
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    lineHeight: 1.15
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space2
                    visible: actionRepeater.count > 0
                    spacing: Theme.space2

                    Repeater {
                        id: actionRepeater

                        model: root.notification
                            ? Array.from(root.notification.actions).filter(action => action.identifier !== "default").slice(0, 2)
                            : []

                        PillButton {
                            required property var modelData
                            required property int index
                            compact: true
                            primary: index === 0
                            text: modelData.text
                            onClicked: modelData.invoke()
                        }
                    }
                }
            }

            BarButton {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 24
                implicitHeight: 24
                glyph: "window-close-symbolic"
                label: "Dismiss"
                onClicked: root.goAway(true)
            }
        }

        // The wait: a 2 px accent bar along the bottom (clear of the rounded corners),
        // shrinking towards the right.
        Rectangle {
            visible: !root.critical
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: card.radius - 2
            anchors.bottomMargin: 1
            width: (parent.width - (card.radius - 2) * 2) * root.remaining
            height: 2
            color: Theme.accent
            opacity: 0.9
        }
    }
}
