// Graphite Desk, generated from design/graphite-desk/tokens.json by scripts/gen-qml-theme.js.
// Do not edit: change the tokens and run `npm run build:qml-theme`.
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    // Dark unless the shell is told otherwise (Settings, or the system's colour scheme).
    property bool dark: true

    readonly property color backdrop: dark ? "#141516" : "#dcdad6"
    readonly property color backdropGlow: dark ? "#25262a" : "#ebe9e5"
    readonly property color surface100: dark ? "#232427" : "#f4f3f1"
    readonly property color surface200: dark ? "#2e2f32" : "#ffffff"
    readonly property color surface300: dark ? "#3b3c40" : "#e7e5e1"
    readonly property color header: dark ? "#2a2b2e" : "#efeeeb"
    readonly property color sidebar: dark ? "#b81e1f22" : "#bdf4f3f1"
    readonly property color glassEdge: dark ? "#17ffffff" : "#14000000"
    readonly property color glassSheen: dark ? "#0affffff" : "#99ffffff"
    readonly property color scrim: dark ? "#9e08080a" : "#61141416"
    readonly property color line: dark ? "#35363a" : "#dedbd6"
    readonly property color lineStrong: dark ? "#7a7c82" : "#8a877f"
    readonly property color ink: dark ? "#ededec" : "#1c1d1f"
    readonly property color inkMuted: dark ? "#a6a7aa" : "#5a5c60"
    readonly property color accent: dark ? "#e3ab4f" : "#83550d"
    readonly property color accentSoft: dark ? "#40331f" : "#f3e4c8"
    readonly property color onAccent: dark ? "#141516" : "#ffffff"
    readonly property color danger: dark ? "#ec8276" : "#b0372c"
    readonly property color success: dark ? "#97c582" : "#356922"
    readonly property color tagBlue: dark ? "#7ea6ea" : "#3a66b5"
    readonly property color tagGreen: dark ? "#7fc28e" : "#357a45"
    readonly property color tagViolet: dark ? "#ad97e4" : "#6f55b5"
    readonly property color tagRose: dark ? "#e48da4" : "#a8445f"
    readonly property color tagTeal: dark ? "#6ec3c0" : "#27787a"
    readonly property color key: dark ? "#36373b" : "#ecebe8"

    readonly property string fontSans: "Inter"
    readonly property string fontMono: "JetBrains Mono"
    readonly property real displaySize: 28
    readonly property real displayLine: 34
    readonly property int displayWeight: 700
    readonly property string displayFamily: fontSans
    readonly property real nameSize: 20
    readonly property real nameLine: 28
    readonly property int nameWeight: 400
    readonly property string nameFamily: fontSans
    readonly property real bodySize: 14
    readonly property real bodyLine: 22
    readonly property int bodyWeight: 400
    readonly property string bodyFamily: fontSans
    readonly property real actionSize: 13
    readonly property real actionLine: 18
    readonly property int actionWeight: 500
    readonly property string actionFamily: fontSans
    readonly property real stripSize: 12
    readonly property real stripLine: 16
    readonly property int stripWeight: 500
    readonly property string stripFamily: fontSans
    readonly property real hintSize: 11
    readonly property real hintLine: 14
    readonly property int hintWeight: 400
    readonly property string hintFamily: fontSans
    readonly property real terminalSize: 14
    readonly property real terminalLine: 20
    readonly property int terminalWeight: 400
    readonly property string terminalFamily: fontMono
    readonly property real identifierSize: 11
    readonly property real identifierLine: 16
    readonly property int identifierWeight: 500
    readonly property string identifierFamily: fontMono
    readonly property real keySize: 11
    readonly property real keyLine: 16
    readonly property int keyWeight: 500
    readonly property string keyFamily: fontMono

    readonly property real space1: 4
    readonly property real space2: 8
    readonly property real space3: 12
    readonly property real space4: 16
    readonly property real space6: 24
    readonly property real space10: 40
    readonly property real radiusSm: 6
    readonly property real radiusMd: 12
    readonly property real radiusLg: 16
    readonly property real radiusFull: 999
    readonly property real stripHeight: 40
    readonly property real taskbarHeight: 48
    readonly property real iconButton: 40
    readonly property real toastWidth: 360
    readonly property real blurGlass: 24
    readonly property real keyHeight: 20
    readonly property real launcherWidth: 720
    readonly property real appTile: 44
    readonly property real durationInstant: 80
    readonly property real durationFast: 140
    readonly property real durationBase: 220
    readonly property real durationSlow: 320
    readonly property real durationIntro: 1600
    readonly property real stagger: 30
    readonly property real durationMerge: 280
    readonly property real rise: 8
    readonly property real slide: 24
    readonly property real rowCompact: 28
    readonly property real rowComfy: 36
    readonly property real rowSpacious: 56
    readonly property real iconList: 16
    readonly property real iconListLarge: 24
    readonly property real sidebarWidth: 220

    readonly property var easeEnter: [0.16, 1, 0.3, 1, 1, 1]
    readonly property var easeExit: [0.4, 0, 1, 1, 1, 1]
    readonly property var easeStandard: [0.2, 0, 0, 1, 1, 1]
}
