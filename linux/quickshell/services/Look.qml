pragma Singleton
// The look chosen on the Control Panel's Personalisation page: the accent, background blur,
// the animation speed, whether windows animate, and the live wallpaper (Backdrop.qml). The
// shell follows them through Theme (shell.qml binds them); Hyprland through desk.lua, where
// Displays.write() puts luaLines() for hyprland.lua to read after everything else (its look()
// and the blur).
import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var values: ShellSettings.values || ({})
    readonly property string accent: values.accent || "indigo"
    readonly property bool blur: values.blur !== false
    readonly property real speed: Number(values.animationSpeed) || 1
    readonly property bool windowAnimations: values.windowAnimations !== false
    readonly property bool liveWallpaper: values.liveWallpaper !== false

    // The speeds offered: half as fast to half as fast again, in quarters.
    readonly property var speeds: [0.5, 0.75, 1, 1.25, 1.5]

    function setAccent(name) {
        ShellSettings.set("accent", name);
    }

    function setBlur(on) {
        ShellSettings.set("blur", on);
        Displays.write();
    }

    function setSpeed(value) {
        ShellSettings.set("animationSpeed", value);
        Displays.write();
    }

    function setLiveWallpaper(on) {
        ShellSettings.set("liveWallpaper", on);
    }

    function setWindowAnimations(on) {
        ShellSettings.set("windowAnimations", on);
        Displays.write();
    }

    // For desk.lua: what hyprland.lua reads after loading it.
    function luaLines() {
        return [`graphite_look = { speed = ${speed}, window_animations = ${windowAnimations}, blur = ${blur} }`];
    }
}
