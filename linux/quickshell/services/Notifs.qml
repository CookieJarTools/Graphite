// The shell is the notification server (org.freedesktop.Notifications): every app's
// notifications come here, show as pop-ups in the top-right corner (Toasts.qml) and stay
// listed in the calendar panel until dismissed.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property int popupMilliseconds: 6000
    readonly property int mostKept: 50
    readonly property int mostPopups: 3

    // [{ notification, time }], newest first.
    property var history: []
    property var popups: []

    // A dot on the clock while something arrived since the calendar was last opened.
    property real seenUntil: Date.now()
    readonly property bool unseen: history.some(entry => entry.time > seenUntil)

    NotificationServer {
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notification => {
            notification.tracked = true;
            const entry = { notification: notification, time: Date.now() };
            root.history = [entry].concat(root.history).slice(0, root.mostKept);
            root.popups = [entry].concat(root.popups).slice(0, root.mostPopups);
            notification.closed.connect(() => root.forget(notification));
        }
    }

    function forget(notification) {
        history = history.filter(entry => entry.notification !== notification);
        popups = popups.filter(entry => entry.notification !== notification);
    }

    // Off the screen, still in the calendar's list.
    function hidePopup(notification) {
        popups = popups.filter(entry => entry.notification !== notification);
    }

    function dismiss(notification) {
        notification.dismiss(); // its closed signal forgets it
    }

    // The app's default action ("default"), as a click on the notification.
    function open(notification) {
        const action = Array.from(notification.actions).find(candidate => candidate.identifier === "default");
        if (action) action.invoke();
        else dismiss(notification);
    }

    function clearAll() {
        for (const entry of history.slice()) entry.notification.dismiss();
        history = [];
        popups = [];
    }

    function markSeen() {
        seenUntil = Date.now();
    }
}
