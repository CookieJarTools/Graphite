// The shell's look: Vesper (graphite surfaces, 1px hairlines, tight Inter type, one accent,
// short purposeful motion). Every surface draws its colours, type, spacing, radii and timings
// from here. Written by hand: it no longer comes from design/graphite/tokens.json, which still
// styles the Windows version. The apps' dark GTK colours (scripts/gen-gtk-theme.js) and the
// terminal's (linux/kitty/vesper.conf) copy these; services/Desktop.qml hands them the accent.
//
// shell.qml sets the four choices below from the Control Panel's Personalisation page
// (settings.json); the login screen keeps their defaults.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: theme

    // Dark unless the shell is told otherwise (Settings, or the time of day). The light
    // colours are Graphite's own: Vesper has no light theme yet.
    property bool dark: true
    // "indigo", "blue", "mint", "amber" or "rose".
    property string accentName: "indigo"
    // Off, the see-through surfaces (taskbar, toasts, launcher) turn solid.
    property bool blur: true
    // Every duration is divided by this: 0.5 is half as fast, 1.5 half as fast again.
    property real speed: 1
    // Window animations off: every transition becomes a short fade, nothing moves or scales.
    property bool reducedMotion: false

    // ---------- colour ----------

    // Each accent: the colour itself (indicators, progress, the selection tint), a fill for
    // buttons with `onFill` text on it (4.5:1 or better), and a lighter one for text and focus.
    readonly property var accents: ({
        indigo: { accent: "#6E79F2", fill: "#5B63E6", text: "#9AA2FF", onFill: "#FFFFFF", name: "Indigo" },
        blue: { accent: "#3B9BEB", fill: "#2A78C2", text: "#8CC4F5", onFill: "#FFFFFF", name: "Blue" },
        mint: { accent: "#3FBF9B", fill: "#3FBF9B", text: "#7FDDBF", onFill: "#08090B", name: "Mint" },
        amber: { accent: "#E0A24A", fill: "#E0A24A", text: "#F0C47F", onFill: "#08090B", name: "Amber" },
        rose: { accent: "#E5729A", fill: "#C24D78", text: "#F2A5BF", onFill: "#FFFFFF", name: "Rose" }
    })
    readonly property var accentNames: ["indigo", "blue", "mint", "amber", "rose"]
    readonly property var accentSet: accents[accentName] || accents.indigo

    // Surfaces, darkest first.
    readonly property color wallpaper: dark ? "#08090B" : "#dcdad6"
    readonly property color sidebar: dark ? "#0B0C0E" : "#ecebe8"
    readonly property color window: dark ? "#0F1012" : "#f4f3f1"
    readonly property color panel: dark ? "#131417" : "#ffffff"
    readonly property color raised: dark ? "#16171B" : "#ffffff"

    // Text: primary, secondary (and inactive icons), labels and hints.
    readonly property color ink: dark ? "#EDEEF0" : "#1c1d1f"
    readonly property color inkMuted: dark ? "#A0A3AB" : "#5a5c60"
    readonly property color inkFaint: dark ? "#8A8F98" : "#6b6d72"

    readonly property color accent: dark ? accentSet.accent : accentSet.fill
    readonly property color accentFill: accentSet.fill
    readonly property color onAccent: accentSet.onFill
    readonly property color accentText: dark ? accentSet.text : Qt.darker(accentSet.fill, 1.25)
    // A selected list row: the accent at 16%.
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.16)

    readonly property color success: dark ? "#6FD3A4" : "#2f7a55"
    readonly property color warning: dark ? "#EDB96B" : "#8a5a12"
    readonly property color danger: dark ? "#F08A8A" : "#b0372c"

    // Hairlines: around windows, panels and toasts; rules inside them.
    readonly property color border: dark ? "#17ffffff" : "#1a000000"
    readonly property color divider: dark ? "#12ffffff" : "#14000000"
    // Tints over any surface: a row under the pointer, an icon button under it, the chosen
    // sidebar item.
    readonly property color hoverRow: dark ? "#0dffffff" : "#0a000000"
    readonly property color hoverIcon: dark ? "#14ffffff" : "#10000000"
    readonly property color activeRow: dark ? "#12ffffff" : "#0f000000"
    // Settings groups and stat tiles.
    readonly property color cardFill: dark ? "#05ffffff" : "#05000000"
    readonly property color cardBorder: dark ? "#14ffffff" : "#14000000"
    // Controls: a switch while off, a segment while chosen, a quick-settings tile while off,
    // a slider's empty track.
    readonly property color switchOff: dark ? "#24ffffff" : "#24000000"
    readonly property color segmentOn: dark ? "#1affffff" : "#ffffff"
    readonly property color tileOff: dark ? "#0fffffff" : "#0d000000"
    readonly property color track: dark ? "#1fffffff" : "#1f000000"

    // The desktop: the glow from the top, the grid, the dimming behind the launcher, the
    // taskbar's running dot and its handle while hidden.
    readonly property color glow: dark ? Qt.rgba(99 / 255, 102 / 255, 232 / 255, 0.24) : Qt.rgba(99 / 255, 102 / 255, 232 / 255, 0.12)
    readonly property color gridLine: dark ? "#09ffffff" : "#0d000000"
    readonly property color scrim: dark ? Qt.rgba(4 / 255, 5 / 255, 7 / 255, 0.5) : Qt.rgba(20 / 255, 20 / 255, 22 / 255, 0.3)
    readonly property color runningDot: dark ? "#73ffffff" : "#73000000"
    readonly property color handle: dark ? "#38ffffff" : "#38000000"
    readonly property color sheen: dark ? "#0affffff" : "#99ffffff"

    // A surface over blur: see-through by `alpha` while blur is on, solid when it's off.
    function glass(colour, alpha) {
        return Qt.rgba(colour.r, colour.g, colour.b, blur ? alpha : 1);
    }

    // A colour at a given strength (the 16% tints behind toast and menu icons).
    function tint(colour, alpha) {
        return Qt.rgba(colour.r, colour.g, colour.b, alpha);
    }

    // Graphite's names, kept so every surface reads the new values.
    readonly property color backdrop: wallpaper
    readonly property color backdropGlow: glow
    readonly property color surface100: window
    readonly property color surface200: panel
    readonly property color surface300: activeRow
    readonly property color header: window
    readonly property color glassEdge: border
    readonly property color glassSheen: sheen
    readonly property color line: divider
    readonly property color lineStrong: dark ? "#29ffffff" : "#33000000"
    readonly property color key: dark ? "#0fffffff" : "#ecebe8"
    readonly property color tagBlue: dark ? "#7ea6ea" : "#3a66b5"
    readonly property color tagGreen: dark ? "#6FD3A4" : "#357a45"
    readonly property color tagViolet: dark ? "#ad97e4" : "#6f55b5"
    readonly property color tagRose: dark ? "#E5729A" : "#a8445f"
    readonly property color tagTeal: dark ? "#6ec3c0" : "#27787a"

    // ---------- type ----------
    // Inter for the interface, JetBrains Mono for paths, PIDs and shortcuts. Qt sizes type in
    // whole pixels, so the half sizes round: 13.5 to 14, 12.5 to 12, 11.5 to 11 (mono 12).

    readonly property string fontSans: "Inter"
    readonly property string fontMono: "JetBrains Mono"

    readonly property real headingSize: 20     // window heading, 600
    readonly property real labelSize: 14       // a setting's or a result's label, 500
    readonly property real bodySize: 13        // body and list rows, 400
    readonly property real titleSize: 13       // window title, sidebar item, 500
    readonly property real hintSize: 12        // hints, inkFaint
    readonly property real sectionSize: 11     // section and column labels, 500, inkFaint
    readonly property real identifierSize: 12  // mono
    readonly property real clockSize: 132      // the lock screen's time, 300

    readonly property int bodyWeight: 400
    readonly property int labelWeight: 500
    readonly property int headingWeight: 600

    readonly property real displaySize: 24
    readonly property int displayWeight: 600
    readonly property real nameSize: headingSize
    readonly property real actionSize: 13      // buttons and fields
    readonly property real stripSize: 13       // the taskbar's labels and time
    readonly property int stripWeight: 500
    readonly property real keySize: 11

    // ---------- spacing, radius, size ----------

    readonly property real space1: 4
    readonly property real space2: 8
    readonly property real space3: 12
    readonly property real space4: 16
    readonly property real space5: 20
    readonly property real space6: 24
    readonly property real space7: 28
    readonly property real space9: 36
    readonly property real space10: 40

    readonly property real radiusSm: 6       // menu row
    readonly property real radiusRow: 7      // list row, icon button
    readonly property real radiusControl: 8  // button, field
    readonly property real radiusCard: 10    // card, taskbar button, menu
    readonly property real radiusMd: 12      // window, toast
    readonly property real radiusLg: 14      // launcher, quick settings, panels
    readonly property real radiusBar: 16     // taskbar
    readonly property real radiusFull: 999

    readonly property real barButton: 44
    readonly property real barPadding: 6
    readonly property real barInset: 14       // the taskbar's gap above the screen's edge
    readonly property real taskbarHeight: barButton + barPadding * 2
    readonly property real barTop: taskbarHeight + barInset   // the taskbar's top, from the screen's bottom
    readonly property real iconButton: 28
    readonly property real toastWidth: 340
    readonly property real launcherWidth: 560
    readonly property real launcherTop: 190
    readonly property real keyHeight: 20
    readonly property real appTile: 44
    readonly property real rowCompact: 30
    readonly property real rowComfy: 32
    readonly property real rowSpacious: 56
    readonly property real iconList: 16
    readonly property real iconListLarge: 24
    readonly property real sidebarWidth: 224

    // ---------- icons ----------
    // Outline icons drawn for the shell (assets/icons: a 24 px grid, 1.7 px strokes, round caps
    // and joins, in white for Glyph to tint). A glyph's name without "-symbolic" finds its
    // file; any other comes from the icon theme (Papirus).

    readonly property var drawnIcons: {
        const names = [
            "airplane-mode", "application-x-executable", "audio-volume-high", "audio-volume-muted",
            "avatar-default", "battery-good", "bluetooth-active", "computer", "dialog-error",
            "dialog-information", "dialog-warning", "drive-harddisk", "edit-clear-all",
            "edit-delete", "emblem-system", "folder", "go-down", "go-next", "go-previous", "go-up",
            "input-keyboard", "list-add", "media-playback-pause", "media-playback-start",
            "media-skip-backward", "media-skip-forward", "network-wired", "network-wireless",
            "network-wireless-signal-excellent", "night-light", "notifications", "object-select",
            "pan-down", "pan-end", "pan-start", "pan-up", "preferences-desktop-appearance",
            "preferences-system-time", "security-high", "software-update-available", "speedometer",
            "system-lock-screen", "system-log-out", "system-reboot", "system-run", "system-search",
            "system-shutdown", "system-software-install", "system-suspend",
            "utilities-system-monitor", "video-display", "view-app-grid", "view-list-bullet",
            "view-more", "window-close"
        ];
        const set = {};
        for (const name of names) set[name] = true;
        return set;
    }

    function iconFor(name) {
        // Wi-Fi at any strength is the one outline (its strength is said in words beside it).
        const base = String(name || "").replace(/-symbolic$/, "").replace(/^network-wireless-signal-(excellent|good|ok|weak)$/, "network-wireless");
        return drawnIcons[base] ? Qt.resolvedUrl("../assets/icons/" + base + ".svg") : "";
    }

    // ---------- motion ----------
    // Durations in milliseconds, through ms(): scaled by `speed`, and a short fade at most with
    // reduced motion. Distances and scales through move() and grow(), which drop to none.

    function ms(value) {
        return reducedMotion ? Math.min(value, 120) : Math.round(value / Math.max(0.25, speed));
    }

    function move(value) {
        return reducedMotion ? 0 : value;
    }

    function grow(value) {
        return reducedMotion ? 1 : value;
    }

    readonly property real durationInstant: ms(140)  // hover and press
    readonly property real durationFast: ms(160)     // what leaves
    readonly property real durationBase: ms(220)     // what arrives
    readonly property real durationSlow: ms(360)
    readonly property real durationIntro: ms(1600)

    readonly property real durationWindowOpen: ms(280)
    readonly property real durationWindowClose: ms(160)
    readonly property real durationToastIn: ms(360)
    readonly property real durationToastOut: ms(380)
    readonly property real durationLauncherIn: ms(220)
    readonly property real durationScrim: ms(180)
    readonly property real durationBarMove: ms(420)
    readonly property real durationBarFade: ms(260)
    readonly property real durationLift: ms(220)
    readonly property real durationIndicator: ms(260)
    readonly property real durationKnob: ms(240)
    readonly property real durationLock: ms(700)
    readonly property real lockStagger: ms(140)
    readonly property real durationBars: ms(600)
    readonly property real stagger: ms(30)
    readonly property real durationMerge: ms(280)

    readonly property real rise: move(8)
    readonly property real slide: move(28)

    // Bezier curves as QML takes them ([x1, y1, x2, y2, 1, 1]).
    readonly property var easeOut: [0.2, 0.9, 0.2, 1, 1, 1]        // entrances
    readonly property var easeToast: [0.2, 0.9, 0.2, 1.1, 1, 1]    // a toast arriving
    readonly property var easeSpring: [0.2, 0.9, 0.2, 1.2, 1, 1]   // hover lift, indicator, switch knob
    readonly property var easeInOut: [0.4, 0, 0.2, 1, 1, 1]        // a toast leaving
    readonly property var easeIn: [0.42, 0, 1, 1, 1, 1]            // exits
    readonly property var ease: [0.25, 0.1, 0.25, 1, 1, 1]         // hover and press
    readonly property var easeMinimise: [0.5, 0, 0.8, 0.4, 1, 1]

    readonly property var easeEnter: easeOut
    readonly property var easeExit: easeIn
    readonly property var easeStandard: easeInOut
}
