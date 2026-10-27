// The calendar: today, a month to page through, and every notification still kept.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

PanelFrame {
    id: root

    name: "calendar"
    panelWidth: 340

    property date month: firstOfMonth(new Date())

    onOpenChanged: {
        if (!open) return;
        month = firstOfMonth(new Date());
        Notifs.markSeen();
    }

    function firstOfMonth(day) {
        return new Date(day.getFullYear(), day.getMonth(), 1);
    }

    // Six weeks from the week holding the 1st, starting on the region's first weekday.
    function weeks(first) {
        const weekStart = Qt.locale().firstDayOfWeek % 7; // 0 = Sunday
        const lead = (first.getDay() - weekStart + 7) % 7;
        const today = new Date().toDateString();
        const days = [];
        for (let index = 0; index < 42; index++) {
            const day = new Date(first.getFullYear(), first.getMonth(), 1 - lead + index);
            days.push({ number: day.getDate(), inMonth: day.getMonth() === first.getMonth(), today: day.toDateString() === today });
        }
        return days;
    }

    function weekdayNames() {
        const weekStart = Qt.locale().firstDayOfWeek % 7;
        const names = [];
        for (let index = 0; index < 7; index++) {
            const day = new Date(2024, 0, 7 + (weekStart + index) % 7); // 7 January 2024 was a Sunday
            names.push(Qt.formatDate(day, "ddd").slice(0, 1));
        }
        return names;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        spacing: 0

        UiText {
            text: Qt.formatDate(clock.date, "dddd")
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }

        UiText {
            text: Qt.formatDate(clock.date, "d MMMM yyyy")
            color: Theme.inkMuted
        }
    }

    RowLayout {
        Layout.fillWidth: true

        UiText {
            Layout.fillWidth: true
            text: Qt.formatDate(root.month, "MMMM yyyy")
            font.weight: Font.DemiBold
        }

        BarButton {
            glyph: "go-previous-symbolic"
            onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() - 1, 1)
        }

        BarButton {
            glyph: "go-next-symbolic"
            onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() + 1, 1)
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: root.weekdayNames()

            UiText {
                required property var modelData
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }
        }

        Repeater {
            model: root.weeks(root.month)

            Rectangle {
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: modelData.today ? Theme.accent : "transparent"

                UiText {
                    anchors.centerIn: parent
                    text: parent.modelData.number
                    color: parent.modelData.today ? Theme.onAccent : Theme.ink
                    opacity: parent.modelData.inMonth ? 1 : 0.4
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.identifierSize
                    font.weight: parent.modelData.today ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.line
    }

    RowLayout {
        Layout.fillWidth: true

        UiText {
            Layout.fillWidth: true
            text: "Notifications"
            font.weight: Font.DemiBold
        }

        MenuRow {
            visible: Notifs.history.length > 0
            text: "Clear all"
            onClicked: Notifs.clearAll()
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: Notifs.history.length === 0
        horizontalAlignment: Text.AlignHCenter
        text: "No new notifications"
        color: Theme.inkMuted
    }

    ListView {
        Layout.fillWidth: true
        visible: Notifs.history.length > 0
        implicitHeight: Math.min(contentHeight, 260)
        clip: true
        spacing: Theme.space2
        model: Notifs.history

        delegate: NoteCard { width: ListView.view.width }
    }
}
