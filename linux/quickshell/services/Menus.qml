pragma Singleton
// The bar's menus, as rows for Menu.qml: an app's, a window's, a folder's, the bar's own (a
// right click on its empty part), and the tags one for a window. `at` is where a menu opens:
// { screen, x, y, above }.

import QtQuick
import Quickshell
import qs.config

Singleton {
    id: root

    readonly property var separator: ({ separator: true })

    function open(at, items) {
        ShellState.openMenu(at.screen, at.x, at.y, at.above, items);
    }

    function windowTitle(window) {
        const title = window.title || "Untitled window";
        return title.length > 48 ? title.slice(0, 47) + "…" : title;
    }

    // A window's tags: tick one to put it on (ticked again takes it off), or make a new one.
    function tagItems(window, at) {
        const current = window.tag ? window.tag.id : null;
        const tags = ShellSettings.taskbar.tags || [];
        const rows = tags.map(tag => ({
            text: tag.name,
            checked: tag.id === current,
            colour: Taskbar.tagColour(tag.color),
            action: () => Taskbar.tagWindow(window.hwnd, tag.id === current ? null : tag.id)
        }));
        if (rows.length) rows.push(separator);
        rows.push({ text: "New tag...", action: () => ShellState.openTagPanel(at.screen, window.hwnd, window.title, at.x) });
        if (current) rows.push({ text: "Remove tag", action: () => Taskbar.tagWindow(window.hwnd, null) });
        return rows;
    }

    // An app's pill (or an app inside a folder's list, `folder` being that folder).
    function appItems(item, at, folder) {
        const rows = [];
        if (Apps.canRunAsAdmin(item.key)) rows.push({ text: "New window", action: () => Apps.launchKey(item.key) });
        if (folder) rows.push({ text: "Remove from folder", action: () => Taskbar.removeFromFolder(folder.id, item.key) });
        else rows.push({ text: item.pinned ? "Unpin from taskbar" : "Pin to taskbar", action: () => Taskbar.setPinned(item, !item.pinned) });
        if (Apps.canRunAsAdmin(item.key)) rows.push({ text: "Run as administrator", action: () => Apps.runAsAdmin(item.key) });

        const windows = item.windows;
        if (windows.length > 0) rows.push(separator);
        if (windows.length === 1) {
            rows.push({ text: "Tag window", submenu: tagItems(windows[0], at) });
        } else if (windows.length > 1) {
            // One row per window; choosing one shows that window's tags in its place.
            rows.push({
                text: "Tag a window",
                submenu: windows.map(window => ({
                    text: windowTitle(window),
                    colour: window.tag ? Taskbar.tagColour(window.tag.color) : undefined,
                    action: () => open(at, tagItems(window, at))
                }))
            });
        }
        if (windows.length === 1) rows.push({ text: "Minimise", action: () => Taskbar.minimize(windows[0].hwnd) });
        if (windows.length > 0) {
            rows.push({
                text: windows.length > 1 ? "Close all " + windows.length + " windows" : "Close window",
                action: () => windows.forEach(window => Taskbar.closeWindow(window.hwnd))
            });
        }
        return rows;
    }

    // A window's row in a pill's list.
    function windowItems(window, at) {
        return [
            { text: "Tag window", submenu: tagItems(window, at) },
            separator,
            { text: "Minimise", visible: !window.minimized, action: () => Taskbar.minimize(window.hwnd) },
            { text: "Close window", action: () => Taskbar.closeWindow(window.hwnd) }
        ];
    }

    function folderItems(item) {
        return [
            { text: "Rename", action: () => { ShellState.renaming = item.id; } },
            { text: item.pinned ? "Unpin folder" : "Pin folder", action: () => Taskbar.setFolderPinned(item.id, !item.pinned) },
            item.label
                ? { text: "Remove category", action: () => Taskbar.unpinCategory(item.label) }
                : { text: "Ungroup", action: () => Taskbar.ungroup(item.id) }
        ];
    }

    // The bar's own menu.
    function barItems() {
        const taskbar = ShellSettings.taskbar;
        const rows = [
            { text: "Show app names", checked: taskbar.showLabels !== false, action: () => ShellSettings.setTaskbar("showLabels", taskbar.showLabels === false) },
            { text: "Always auto-hide", checked: !!taskbar.alwaysAutoHide, action: () => ShellSettings.setTaskbar("alwaysAutoHide", !taskbar.alwaysAutoHide) },
            { text: "Auto-hide when a window is maximised", checked: !!taskbar.autoHideWhenMaximised, enabled: !taskbar.alwaysAutoHide, action: () => ShellSettings.setTaskbar("autoHideWhenMaximised", !taskbar.autoHideWhenMaximised) },
            separator,
            { text: "Tile windows", checked: !!(ShellSettings.values && ShellSettings.values.tiling), action: () => Taskbar.setTiling(!(ShellSettings.values && ShellSettings.values.tiling)) },
            separator,
            {
                text: "Pin category",
                submenu: Taskbar.labels.map(label => ({
                    text: label,
                    checked: Taskbar.categoryPinned(label),
                    action: () => Taskbar.categoryPinned(label) ? Taskbar.unpinCategory(label) : Taskbar.pinCategory(label)
                }))
            }
        ];
        const tags = taskbar.tags || [];
        if (tags.length) {
            rows.push(separator);
            rows.push({
                text: "Delete tag",
                submenu: tags.map(tag => ({ text: tag.name, colour: Taskbar.tagColour(tag.color), action: () => Taskbar.deleteTag(tag.id) }))
            });
        }
        rows.push(separator);
        rows.push({ text: "Taskbar settings", action: () => ShellState.openSettings() });
        return rows;
    }
}
