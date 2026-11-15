// The calendar: today, a month to page through, and every notification still kept.
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.services

PanelFrame {
    id: root

    name: "calendar"
    panelWidth: 320

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
            font.pixelSize: Theme.headingSize
            font.weight: Theme.headingWeight
            font.letterSpacing: -0.2
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
            font.weight: Theme.labelWeight
        }

        BarButton {
            implicitWidth: 28
            implicitHeight: 28
            glyph: "go-previous-symbolic"
            label: "Previous month"
            onClicked: root.month = new Date(root.month.getFullYear(), root.month.getMonth() - 1, 1)
        }

        BarButton {
            implicitWidth: 28
            implicitHeight: 28
            glyph: "go-next-symbolic"
            label: "Next month"
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
                color: Theme.inkFaint
                font.pixelSize: Theme.sectionSize
                font.weight: Theme.labelWeight
            }
        }

        Repeater {
            model: root.weeks(root.month)

            Rectangle {
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: modelData.today ? Theme.accentFill : "transparent"

                UiText {
                    anchors.centerIn: parent
                    text: parent.modelData.number
                    color: parent.modelData.today ? Theme.onAccent : parent.modelData.inMonth ? Theme.ink : Theme.inkFaint
                    opacity: parent.modelData.inMonth || parent.modelData.today ? 1 : 0.6
                    font.pixelSize: Theme.bodySize
                    font.features: { "tnum": 1 }
                    font.weight: parent.modelData.today ? Theme.headingWeight : Theme.bodyWeight
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.divider
    }

    RowLayout {
        Layout.fillWidth: true

        UiText {
            Layout.fillWidth: true
            text: "Notifications"
            color: Theme.inkFaint
            font.pixelSize: Theme.sectionSize
            font.weight: Theme.labelWeight
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
        color: Theme.inkFaint
        font.pixelSize: Theme.hintSize
    }

    ListView {
        id: noteList
        Layout.fillWidth: true
        visible: Notifs.history.length > 0
        implicitHeight: Math.min(contentHeight, 260)
        clip: true
        spacing: Theme.space2
        model: Notifs.history

        WheelScroll { flickable: noteList }

        delegate: NoteCard { width: ListView.view.width }
    }
}
