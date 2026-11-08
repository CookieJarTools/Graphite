pragma Singleton
// The shell is the notification server (org.freedesktop.Notifications): every app's
// notifications come here, show as pop-ups in the top-right corner (Toasts.qml) and stay
// listed in the calendar panel until dismissed. A click on one leads to where it came from.

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
    // Kept in settings, so a restart of the shell does not bring the dot back.
    readonly property real seenUntil: ShellSettings.values ? ShellSettings.values.notificationsSeen || 0 : Date.now()
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
            // Its sound: the one it names (the freedesktop sound-name hint), none if it asks for
            // quiet, else by how urgent it is.
            const hints = notification.hints || {};
            const icon = notification.appIcon || "";
            if (!hints["suppress-sound"]) Sounds.play(hints["sound-name"] ? String(hints["sound-name"])
                : notification.urgency === NotificationUrgency.Critical || /error/.test(icon) ? "error" : /warning/.test(icon) ? "warning" : "notification");
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

    // A click on a notification: the app's own default action ("default") if it has one, and
    // the app brought forward, as an app can't always raise its own window on Wayland; started
    // when it has no window (one in the tray shows itself again). Graphite's own notifications
    // say where they lead, in an "x-graphite-open" hint: a Control Panel page
    // ("settings:updates") or a file.
    function open(notification) {
        const place = String((notification.hints || {})["x-graphite-open"] || "");
        const action = Array.from(notification.actions).find(candidate => candidate.identifier === "default");
        if (action) action.invoke();
        if (place.startsWith("settings:")) ShellState.openSettings(place.slice(9));
        else if (place.startsWith("/")) Quickshell.execDetached(["xdg-open", place]);
        else bringForward(notification);
        hidePopup(notification);
        if (!action) dismiss(notification);
    }

    function bringForward(notification) {
        // notify-send's own name, and Graphite's (its desktop entries are its installer's).
        if (["Graphite", "notify-send", ""].includes(notification.appName || "")) return;
        const entry = Apps.entryFor(notification.desktopEntry) || Apps.entryFor(notification.appName);
        if (!entry) return;
        const window = Taskbar.windows.find(candidate => candidate.key === entry.id);
        if (window) Taskbar.focusWindow(window.hwnd);
        else Apps.launch(entry);
    }

    function clearAll() {
        for (const entry of history.slice()) entry.notification.dismiss();
        history = [];
        popups = [];
    }

    function markSeen() {
        ShellSettings.set("notificationsSeen", Date.now());
    }
}
