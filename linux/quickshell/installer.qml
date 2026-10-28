//@ pragma IconTheme Papirus-Dark
// The Graphite Desk installer's screens, on the USB stick (installer/gui.lua runs it in its own
// Hyprland as the stick's "live" user): a sidebar of steps (how far along, about how long is left) and a card for each step: Welcome, Region, Keyboard, Network, Disk, Account,
// Privacy, Look and feel, Apps, then Installing (a checklist, the bar, tips) and "You're all
// set". Enter continues.
//
// It runs installer/graphite-install.sh as root (sudo) with the answers on its input
// (GRAPHITE_ANSWERS=/dev/stdin, so the password is never written to a file) and follows its
// PROGRESS and STAGE lines. Wi-Fi is joined as root (sudo nmcli), so the install copies it
// into the new system.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.modules
import qs.services

ShellRoot {
    id: root

    readonly property string script: "/usr/share/graphite-desk/linux/installer/graphite-install.sh"

    // ---------- the steps ----------

    // 0 welcome, 1 region, 2 keyboard, 3 network, 4 disk, 5 account, 6 privacy, 7 look,
    // 8 apps, 9 installing, 10 done.
    property int page: 0
    readonly property var steps: ["Region", "Keyboard", "Network", "Disk", "Account", "Privacy", "Look and feel", "Apps", "Installing"]
    readonly property int questions: 8

    function next() {
        if (!canContinue) return;
        if (page === 8) {
            startInstall();
            return;
        }
        if (page === 3 && !online) return;
        page += 1;
    }

    // Back; after a failed install, back to the choices to change them.
    function back() {
        if (page === 9 && failed) {
            failed = false;
            page = 8;
        } else if (page > 0 && page < 9) page -= 1;
    }

    readonly property bool canContinue: {
        switch (page) {
        case 1: return country !== null;
        case 3: return online;
        case 4: return diskChosen !== "" && eraseAgreed;
        case 5: return fullName.text.trim().length > 0 && userName.length > 0 && secret.text.length >= 8 && (pinStore.text.length === 0 || pinStore.text.length === 4);
        default: return page < 9;
        }
    }

    // About how long is left: half a minute for each question, then the install itself.
    readonly property int minutesLeft: page >= 9 ? installMinutesLeft : Math.max(1, Math.round((questions - Math.max(0, page - 1)) * 0.5 + 9))

    // ---------- region ----------

    readonly property var countries: [
        { name: "United Kingdom", lang: "English (UK)", locale: "en_GB.UTF-8", keyboard: "gb", zone: "Europe/London", code: "GB" },
        { name: "United States", lang: "English (US)", locale: "en_US.UTF-8", keyboard: "us", zone: "America/New_York", code: "US" },
        { name: "Ireland", lang: "English (IE)", locale: "en_IE.UTF-8", keyboard: "ie", zone: "Europe/Dublin", code: "IE" },
        { name: "Canada", lang: "English (CA)", locale: "en_CA.UTF-8", keyboard: "us", zone: "America/Toronto", code: "CA" },
        { name: "Australia", lang: "English (AU)", locale: "en_AU.UTF-8", keyboard: "us", zone: "Australia/Sydney", code: "AU" },
        { name: "New Zealand", lang: "English (NZ)", locale: "en_NZ.UTF-8", keyboard: "us", zone: "Pacific/Auckland", code: "NZ" },
        { name: "Germany", lang: "Deutsch", locale: "de_DE.UTF-8", keyboard: "de", zone: "Europe/Berlin", code: "DE" },
        { name: "Austria", lang: "Deutsch", locale: "de_AT.UTF-8", keyboard: "de", zone: "Europe/Vienna", code: "AT" },
        { name: "Switzerland", lang: "Deutsch", locale: "de_CH.UTF-8", keyboard: "ch", zone: "Europe/Zurich", code: "CH" },
        { name: "France", lang: "Français", locale: "fr_FR.UTF-8", keyboard: "fr", zone: "Europe/Paris", code: "FR" },
        { name: "Belgium", lang: "Français", locale: "fr_BE.UTF-8", keyboard: "be", zone: "Europe/Brussels", code: "BE" },
        { name: "Spain", lang: "Español", locale: "es_ES.UTF-8", keyboard: "es", zone: "Europe/Madrid", code: "ES" },
        { name: "Mexico", lang: "Español", locale: "es_MX.UTF-8", keyboard: "us", zone: "America/Mexico_City", code: "MX" },
        { name: "Italy", lang: "Italiano", locale: "it_IT.UTF-8", keyboard: "it", zone: "Europe/Rome", code: "IT" },
        { name: "Netherlands", lang: "Nederlands", locale: "nl_NL.UTF-8", keyboard: "us", zone: "Europe/Amsterdam", code: "NL" },
        { name: "Portugal", lang: "Português", locale: "pt_PT.UTF-8", keyboard: "pt", zone: "Europe/Lisbon", code: "PT" },
        { name: "Brazil", lang: "Português (BR)", locale: "pt_BR.UTF-8", keyboard: "br", zone: "America/Sao_Paulo", code: "BR" },
        { name: "Sweden", lang: "Svenska", locale: "sv_SE.UTF-8", keyboard: "se", zone: "Europe/Stockholm", code: "SE" },
        { name: "Norway", lang: "Norsk", locale: "nb_NO.UTF-8", keyboard: "no", zone: "Europe/Oslo", code: "NO" },
        { name: "Denmark", lang: "Dansk", locale: "da_DK.UTF-8", keyboard: "dk", zone: "Europe/Copenhagen", code: "DK" },
        { name: "Finland", lang: "Suomi", locale: "fi_FI.UTF-8", keyboard: "fi", zone: "Europe/Helsinki", code: "FI" },
        { name: "Poland", lang: "Polski", locale: "pl_PL.UTF-8", keyboard: "pl", zone: "Europe/Warsaw", code: "PL" },
        { name: "India", lang: "English (IN)", locale: "en_IN.UTF-8", keyboard: "us", zone: "Asia/Kolkata", code: "IN" },
        { name: "South Africa", lang: "English (ZA)", locale: "en_ZA.UTF-8", keyboard: "us", zone: "Africa/Johannesburg", code: "ZA" }
    ]
    property var country: countries[0]
    property string timeZone: countries[0].zone

    onCountryChanged: {
        if (!country) return;
        timeZone = country.zone;
        keyboard = country.keyboard;
        if (geo.code === country.code && geo.zone) timeZone = geo.zone;
    }

    // Where the internet says this is, once online: the country, and the time zone within it.
    property var geo: ({ code: "", zone: "" })
    Process {
        id: locate
        command: ["curl", "-s", "--max-time", "6", "https://ipapi.co/json/"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const found = JSON.parse(this.text);
                    root.geo = { code: found.country_code || "", zone: found.timezone || "" };
                    if (root.country && root.geo.code === root.country.code && root.geo.zone) root.timeZone = root.geo.zone;
                } catch (error) {
                    // offline, or the service didn't answer
                }
            }
        }
    }

    // ---------- keyboard ----------

    readonly property var keyboards: [
        { value: "gb", label: "English (UK)" }, { value: "us", label: "English (US)" }, { value: "ie", label: "English (Ireland)" },
        { value: "de", label: "German" }, { value: "fr", label: "French" }, { value: "es", label: "Spanish" },
        { value: "it", label: "Italian" }, { value: "pt", label: "Portuguese" }, { value: "br", label: "Portuguese (Brazil)" },
        { value: "se", label: "Swedish" }, { value: "no", label: "Norwegian" }, { value: "dk", label: "Danish" },
        { value: "fi", label: "Finnish" }, { value: "pl", label: "Polish" }, { value: "ch", label: "Swiss" }, { value: "be", label: "Belgian" }
    ]
    property string keyboard: "gb"
    onKeyboardChanged: Quickshell.execDetached(["hyprctl", "eval", `hl.config({ input = { kb_layout = "${keyboard}" } })`])
    readonly property string keyboardName: (keyboards.find(item => item.value === keyboard) || { label: keyboard }).label

    // ---------- network ----------

    property bool online: false
    property string joining: ""
    property string joinError: ""

    Process {
        id: onlineCheck
        command: ["curl", "-s", "--max-time", "5", "-o", "/dev/null", "-w", "%{http_code}", "https://archlinux.org"]
        stdout: StdioCollector {
            onStreamFinished: {
                const was = root.online;
                root.online = /^[23]/.test(this.text.trim());
                if (root.online && !was) locate.running = true;
            }
        }
    }
    Timer {
        interval: root.online ? 15000 : 3000
        repeat: true
        running: root.page < 9
        triggeredOnStart: true
        onTriggered: if (!onlineCheck.running) onlineCheck.running = true
    }

    Binding {
        target: Network
        property: "windowWatching"
        value: root.page === 3
    }

    function join(network, secret) {
        joining = network.name;
        joinError = "";
        const command = ["sudo", "-n", "nmcli", "device", "wifi", "connect", network.name];
        if (secret) command.push("password", secret);
        joiner.command = command;
        joiner.running = true;
    }

    Process {
        id: joiner
        stderr: StdioCollector { id: joinErrors }
        onExited: code => {
            root.joinError = code === 0 ? "" : /secrets|password|802-1x/i.test(joinErrors.text) ? "That password didn't work" : "Couldn't connect to " + root.joining;
            if (code === 0) onlineCheck.running = true;
            root.joining = "";
        }
    }
    property string networkName: Network.current ? Network.current.name : Network.wired ? "Wired connection" : ""

    // ---------- disk ----------

    property var disks: [] // [{ path, size, model, contents: "windows" | "files" | "empty" }]
    property string diskChosen: ""
    property bool eraseAgreed: false
    readonly property var disk: disks.find(item => item.path === diskChosen) || null

    Process {
        id: diskReader
        command: ["bash", "-c", [
            "live=$(lsblk -no PKNAME \"$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null)\" 2>/dev/null | head -1)",
            "lsblk -dpbno NAME,SIZE,TYPE,MODEL -e 7,11 | while read -r name size type model; do",
            "  [ \"$type\" = disk ] || continue; [ \"/dev/$live\" = \"$name\" ] && continue",
            "  fs=$(lsblk -no FSTYPE \"$name\" | grep -v '^$'); win=empty; [ -n \"$fs\" ] && win=files; grep -q ntfs <<<\"$fs\" && win=windows",
            "  printf '%s\\t%s\\t%s\\t%s\\n' \"$name\" \"$size\" \"${model:-Disk}\" \"$win\"",
            "done"
        ].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.disks = this.text.split("\n").filter(line => line).map(line => line.split("\t"))
                    .map(parts => ({ path: parts[0], size: Number(parts[1]), model: parts[2], contents: parts[3] }));
                if (root.disks.length === 1) root.diskChosen = root.disks[0].path;
            }
        }
    }
    onPageChanged: if (page === 4) diskReader.running = true

    function stepDisk(by) {
        if (page !== 4 || disks.length === 0) return;
        const at = disks.findIndex(item => item.path === diskChosen);
        diskChosen = disks[Math.max(0, Math.min(disks.length - 1, at + by))].path;
        eraseAgreed = false;
    }

    function gigabytes(bytes) {
        return bytes >= 1e12 ? (bytes / 1e12).toFixed(1) + " TB" : Math.round(bytes / 1e9) + " GB";
    }

    // ---------- account ----------

    readonly property string userName: {
        const first = fullName.text.trim().split(" ")[0].toLowerCase().replace(/[^a-z0-9]/g, "");
        return /^[a-z]/.test(first) ? first.slice(0, 30) : first ? "u" + first.slice(0, 29) : "";
    }
    readonly property string hostName: (userName || "graphite") + "-pc"
    readonly property int strength: {
        const text = secret.text;
        if (text.length < 8) return text.length ? 1 : 0;
        let score = 1;
        if (text.length >= 12) score += 1;
        if (/[a-z]/.test(text) && /[A-Z]/.test(text)) score += 1;
        if (/[0-9]/.test(text) && /[^A-Za-z0-9]/.test(text)) score += 1;
        else if (/[0-9]/.test(text) || /[^A-Za-z0-9]/.test(text)) score += 0.5;
        return Math.min(4, Math.floor(score));
    }
    property bool showPassword: false
    property bool triedAccount: false

    // ---------- privacy, look, apps ----------

    property bool encrypt: false
    property bool firewall: true
    property bool autoUpdates: true
    property string theme: "dark"
    Binding {
        target: Theme
        property: "dark"
        value: root.theme === "light" ? false : root.theme === "auto" ? (new Date().getHours() < 7 || new Date().getHours() >= 19) : true
    }

    property bool gaming: false
    // Flathub apps by id; "claude-code" is installed with Anthropic's own installer instead.
    readonly property var appChoices: [
        { id: "app.zen_browser.zen", name: "Zen Browser", tag: "Web" },
        { id: "com.google.Chrome", name: "Google Chrome", tag: "Web" },
        { id: "com.discordapp.Discord", name: "Discord", tag: "Social" },
        { id: "org.telegram.desktop", name: "Telegram", tag: "Social" },
        { id: "com.spotify.Client", name: "Spotify", tag: "Media" },
        { id: "org.videolan.VLC", name: "VLC", tag: "Media" },
        { id: "io.bassi.Amberol", name: "Amberol (music)", tag: "Media" },
        { id: "org.gnome.gThumb", name: "gThumb (photos)", tag: "Photos" },
        { id: "org.gnome.Shotwell", name: "Shotwell (photo library)", tag: "Photos" },
        { id: "com.obsproject.Studio", name: "OBS Studio", tag: "Media" },
        { id: "claude-code", name: "Claude Code", tag: "Dev" },
        { id: "com.visualstudio.code", name: "Visual Studio Code", tag: "Dev" },
        { id: "org.libreoffice.LibreOffice", name: "LibreOffice", tag: "Office" },
        { id: "org.gimp.GIMP", name: "GIMP", tag: "Creative" },
        { id: "org.blender.Blender", name: "Blender", tag: "Creative" },
        { id: "com.valvesoftware.Steam", name: "Steam", tag: "Games" },
        { id: "com.heroicgameslauncher.hgl", name: "Heroic (Epic, GOG, Amazon)", tag: "Games" },
        { id: "net.lutris.Lutris", name: "Lutris (Battle.net, EA, Ubisoft)", tag: "Games" },
        { id: "com.usebottles.bottles", name: "Bottles (Windows apps)", tag: "Games" },
        { id: "com.modrinth.ModrinthApp", name: "Modrinth (Minecraft)", tag: "Games" },
        { id: "io.itch.itch", name: "itch.io", tag: "Games" },
        { id: "net.davidotek.pupgui2", name: "ProtonUp-Qt", tag: "Games" }
    ]
    property var apps: []

    function toggleApp(id) {
        apps = apps.includes(id) ? apps.filter(app => app !== id) : apps.concat([id]);
    }

    function tagColour(tag) {
        return ({ Social: Theme.tagRose, Media: Theme.tagViolet, Photos: Theme.tagTeal, Web: Theme.tagBlue, Dev: Theme.tagBlue, Office: Theme.tagTeal, Creative: Theme.tagGreen, Games: Theme.accent })[tag] || Theme.inkMuted;
    }

    // ---------- installing ----------

    property int percent: 0
    property string stepText: ""
    property string stageNow: ""
    property var stagesDone: []
    property bool failed: false
    property string failText: ""
    property var notes: []
    property double startedAt: 0
    property int installMinutesLeft: 12

    readonly property var stages: [
        { id: "disk", name: "Preparing the disk" },
        { id: "system", name: "Installing Graphite Desk" },
        { id: "account", name: "Setting up your account" },
        { id: "security", name: "Securing this PC" },
        { id: "games", name: "Setting up for games", only: () => root.gaming },
        { id: "apps", name: "Installing " + apps.length + (apps.length === 1 ? " app" : " apps"), only: () => root.apps.length > 0 },
        { id: "finish", name: "Final touches" }
    ].filter(item => !item.only || item.only())

    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    function startInstall() {
        page = 9;
        failed = false;
        percent = 0;
        stagesDone = [];
        stageNow = "";
        startedAt = Date.now();
        const answers = [
            "DISK=" + quote(diskChosen),
            "FULL_NAME=" + quote(fullName.text.trim()),
            "USER_NAME=" + quote(userName),
            "PASSWORD=" + quote(secret.text),
            "HINT=" + quote(hintStore.text.trim()),
            "PIN=" + quote(pinStore.text),
            "HOST_NAME=" + quote(hostName),
            "TIME_ZONE=" + quote(timeZone),
            "KEYBOARD=" + quote(keyboard),
            "LOCALE=" + quote(country.locale),
            "GAMING=" + (gaming ? "yes" : "no"),
            "ENCRYPT=" + (encrypt ? "yes" : "no"),
            "AUTO_UPDATES=" + (autoUpdates ? "yes" : "no"),
            "THEME=" + quote(theme),
            "APPS=" + quote(apps.filter(app => app !== "claude-code").join(" ")),
            "CLAUDE_CODE=" + (apps.includes("claude-code") ? "yes" : "no")
        ].join("\n") + "\n";
        installer.answers = answers;
        installer.running = true;
    }

    Process {
        id: installer
        property string answers: ""
        command: ["sudo", "-n", "env", "GRAPHITE_ANSWERS=/dev/stdin", "GRAPHITE_PROGRESS=lines", "bash", root.script]
        stdinEnabled: true
        onStarted: {
            write(answers);
            answers = "";
            stdinEnabled = false;
        }
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("PROGRESS ")) {
                    const at = line.indexOf(" ", 9);
                    root.percent = parseInt(line.slice(9, at));
                    root.stepText = line.slice(at + 1);
                    const elapsed = (Date.now() - root.startedAt) / 60000;
                    if (root.percent > 5) root.installMinutesLeft = Math.max(1, Math.round(elapsed / root.percent * (100 - root.percent)));
                } else if (line.startsWith("STAGE ")) {
                    if (root.stageNow) root.stagesDone = root.stagesDone.concat([root.stageNow]);
                    root.stageNow = line.slice(6);
                } else if (line.startsWith("ERROR ")) {
                    root.failed = true;
                    root.failText = line.slice(6);
                } else if (line.startsWith("NOTE ")) {
                    root.notes = root.notes.concat([line.slice(5)]);
                } else if (line === "DONE") {
                    root.stagesDone = root.stagesDone.concat([root.stageNow]);
                    root.stageNow = "";
                    root.percent = 100;
                    root.page = 10;
                }
            }
        }
        onExited: code => {
            stdinEnabled = true;
            if (root.page === 9 && !root.failed) {
                root.failed = true;
                root.failText = "The installer stopped unexpectedly.";
            }
        }
    }

    readonly property var tips: [
        "Press the Windows key to search for apps, files and settings.",
        "Ctrl+Shift+Esc opens the Task Manager, as on Windows.",
        "Hold Shift while dragging a window to snap it into a zone.",
        "Updates install from the Control Panel with one click; no typing needed.",
        "Downloaded .deb, AppImage and Flatpak files install themselves when you open them.",
        "Super+Left and Super+Right snap a window to half the screen.",
        "Right-click the taskbar for its settings and the Task Manager."
    ]
    property int tip: 0
    Timer {
        interval: 8000
        repeat: true
        running: root.page === 9
        onTriggered: root.tip = (root.tip + 1) % root.tips.length
    }

    function restart() {
        Quickshell.execDetached(["sudo", "-n", "reboot", "-f"]);
    }

    // ---------- the screen ----------

    PanelWindow {
        id: window
        screen: Quickshell.screens[0]
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.backdrop
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        BackdropGlow { anchors.fill: parent }

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onReturnPressed: root.next()
            Keys.onEnterPressed: root.next()
            Keys.onEscapePressed: root.back()
            // On the disk step: arrows pick a disk, Space switches "Erase ... and install".
            Keys.onSpacePressed: if (root.page === 4 && root.disk) root.eraseAgreed = !root.eraseAgreed
            Keys.onDownPressed: root.stepDisk(1)
            Keys.onUpPressed: root.stepDisk(-1)

            // ---------- the sidebar ----------

            ColumnLayout {
                x: Theme.space6
                y: Theme.space6
                width: 200
                height: parent.height - Theme.space6 * 2
                spacing: Theme.space2

                ColumnLayout {
                    spacing: 0
                    UiText {
                        text: "Graphite Desk"
                        font.weight: Font.DemiBold
                    }
                    UiText {
                        text: "Setting up this PC"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.space4
                    spacing: 2

                    Repeater {
                        model: root.steps

                        Rectangle {
                            id: stepRow
                            required property string modelData
                            required property int index
                            readonly property bool current: root.page === index + 1 || (index === 8 && root.page >= 9)
                            readonly property bool done: root.page > index + 1 && !(index === 8 && root.page === 9)
                            Layout.fillWidth: true
                            implicitHeight: 32
                            radius: Theme.radiusSm
                            color: current ? Theme.surface300 : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space2
                                spacing: Theme.space3

                                Rectangle {
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 8
                                    color: "transparent"
                                    border.color: stepRow.current ? Theme.accent : stepRow.done ? Theme.success : Theme.lineStrong
                                    border.width: 1.5

                                    Rectangle {
                                        visible: stepRow.current
                                        anchors.centerIn: parent
                                        width: 8
                                        height: 8
                                        radius: 4
                                        color: Theme.accent
                                    }

                                    UiText {
                                        visible: stepRow.done
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: Theme.success
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    text: stepRow.modelData
                                    color: stepRow.current || stepRow.done ? Theme.ink : Theme.inkMuted
                                    font.weight: stepRow.current ? Font.DemiBold : Font.Normal
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 2
                    color: Theme.line

                    Rectangle {
                        width: parent.width * (root.page >= 9 ? 0.6 + 0.4 * root.percent / 100 : root.page / 9 * 0.6)
                        height: parent.height
                        color: Theme.ink
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }

                UiText {
                    text: root.page === 10 ? "All done" : "About " + root.minutesLeft + " min left"
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            // ---------- the card ----------

            Rectangle {
                id: card
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 100
                width: Math.min(620, parent.width - 320)
                height: Math.min(560, parent.height - Theme.space10 * 2)
                radius: Theme.radiusLg
                color: Theme.surface200
                border.color: Theme.glassEdge
                border.width: 1

                // Each step rises in as it comes.
                property int shown: root.page
                onShownChanged: enter.restart()
                ParallelAnimation {
                    id: enter
                    NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: 260 }
                    NumberAnimation { target: contentRise; property: "y"; from: 12; to: 0; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeEnter }
                }

                Item {
                    id: content
                    anchors.fill: parent
                    anchors.margins: Theme.space6
                    transform: Translate { id: contentRise }

                    // ----- welcome -----
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: root.page === 0
                        spacing: Theme.space3

                        Mark { Layout.alignment: Qt.AlignHCenter; text: "G" }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Let's set up your PC"
                            font.pixelSize: 26
                            font.weight: Font.Bold
                        }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 400
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: "A few quick choices and you're in. It takes about ten minutes, and you can change everything later in the Control Panel."
                            color: Theme.inkMuted
                        }
                    }

                    // ----- the question steps: a heading, then the step's own content -----
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.page >= 1 && root.page <= 9
                        spacing: Theme.space2

                        UiText {
                            text: root.page === 9 ? "Almost there" : "Step " + root.page + " of " + root.questions
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }

                        UiText {
                            Layout.fillWidth: true
                            text: ["", "Where are you?", "Which keyboard do you have?", "Connect to a network", "Where should Graphite Desk go?", "Who's going to use this PC?", "Privacy and security", "Make it yours", "Install your apps", root.failed ? "Something went wrong" : "Getting everything ready"][root.page] || ""
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }

                        UiText {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Theme.space2
                            wrapMode: Text.WordWrap
                            text: ["",
                                "Sets your language, date format and time zone.",
                                "Type below to check the keys come out right.",
                                "You'll need the internet to install, and for updates and the apps you pick.",
                                "Everything on the disk you choose is erased: Windows, files and photos.",
                                "This is the name you'll see when you sign in.",
                                "Sensible protection, on from the start.",
                                "Pick a look. You can change it any time.",
                                "We'll install these while we finish up. " + root.apps.length + " selected.",
                                root.failed ? root.failText : "This can take a while. Keep your PC plugged in."][root.page] || ""
                            color: root.page === 4 || (root.page === 9 && root.failed) ? Theme.danger : Theme.inkMuted
                        }

                        Loader {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            sourceComponent: [null, regionPage, keyboardPage, networkPage, diskPage, accountPage, privacyPage, lookPage, appsPage, installingPage][root.page] || null
                        }
                    }

                    // ----- done -----
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: root.page === 10
                        spacing: Theme.space3

                        Mark { Layout.alignment: Qt.AlignHCenter; text: "✓" }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "You're all set, " + fullName.text.trim().split(" ")[0]
                            font.pixelSize: 26
                            font.weight: Font.Bold
                        }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Your desk is ready. Restart to sign in."
                            color: Theme.inkMuted
                        }

                        GridLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.space4
                            columns: 2
                            columnSpacing: Theme.space6
                            rowSpacing: Theme.space1

                            // Label, value, label, value...
                            Repeater {
                                model: [
                                    "Region", (root.country ? root.country.name : "") + ", " + root.keyboardName + " keyboard",
                                    "Network", root.networkName || "Not connected",
                                    "Look", ({ dark: "Dark", light: "Light", auto: "Matches the time of day" })[root.theme],
                                    "Apps", root.apps.length + " installed" + (root.gaming ? ", plus games" : ""),
                                    "Security", (root.encrypt ? "Encrypted disk, " : "") + "firewall on"
                                ]

                                UiText {
                                    required property var modelData
                                    required property int index
                                    text: modelData
                                    color: index % 2 === 0 ? Theme.inkMuted : Theme.ink
                                }
                            }
                        }

                        UiText {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Theme.space4
                            text: "Once the screen goes dark, take out the USB stick."
                            color: Theme.inkMuted
                            font.pixelSize: Theme.hintSize
                        }
                    }
                }

                // ----- the footer: Back, Skip, Enter to continue, Continue -----
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.space6
                    visible: root.page !== 9 || root.failed
                    spacing: Theme.space2

                    PillButton {
                        visible: (root.page >= 1 && root.page <= 8) || (root.page === 9 && root.failed)
                        text: "←  Back"
                        onClicked: root.back()
                    }

                    PillButton {
                        visible: root.page === 8
                        text: "Skip for now"
                        onClicked: {
                            root.apps = [];
                            root.next();
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: goText.implicitWidth + Theme.space4 * 2
                        implicitHeight: 34
                        radius: Theme.radiusSm
                        color: Theme.ink
                        opacity: root.canContinue || root.page >= 9 ? (goMouse.containsMouse ? 0.9 : 1) : 0.35

                        UiText {
                            id: goText
                            anchors.centerIn: parent
                            text: root.page === 0 ? "Get started  →" : root.page === 8 ? "Install and finish  →" : root.page === 9 ? "Try again" : root.page === 10 ? "Restart  →" : "Continue  →"
                            color: Theme.surface200
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: goMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.page === 10) root.restart();
                                else if (root.page === 9) root.startInstall();
                                else root.next();
                            }
                        }
                    }
                }
            }
        }
    }

    // The account's fields live here, so their text survives moving between steps.
    FieldBox { id: fullName; visible: false; placeholder: "Your name" }
    FieldBox { id: secret; visible: false; password: true; placeholder: "At least 8 characters" }
    FieldBox { id: hintStore; visible: false; placeholder: "Something only you would understand (optional)" }
    FieldBox { id: pinStore; visible: false }

    // ---------- the steps' contents ----------

    component Mark: Rectangle {
        property alias text: markText.text
        implicitWidth: 48
        implicitHeight: 48
        radius: Theme.radiusMd
        color: Theme.surface300
        border.color: Theme.line

        UiText {
            id: markText
            anchors.centerIn: parent
            font.weight: Font.DemiBold
        }
    }

    // A row to pick, with a round mark on the left.
    component Option: Rectangle {
        id: option
        property string label
        property string detail
        property string glyph
        property bool chosen: false
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 40
        radius: Theme.radiusSm
        color: chosen ? Theme.accentSoft : optionMouse.containsMouse ? Theme.surface300 : Theme.surface100
        border.color: chosen ? Theme.accent : Theme.line
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3
            anchors.rightMargin: Theme.space3
            spacing: Theme.space3

            Rectangle {
                implicitWidth: 14
                implicitHeight: 14
                radius: 7
                color: "transparent"
                border.color: option.chosen ? Theme.accent : Theme.lineStrong
                border.width: 1.5

                Rectangle {
                    visible: option.chosen
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                }
            }

            Glyph {
                visible: option.glyph.length > 0
                name: option.glyph
            }

            UiText {
                Layout.fillWidth: true
                text: option.label
                font.weight: option.chosen ? Font.DemiBold : Font.Normal
            }

            UiText {
                text: option.detail
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }
        }

        MouseArea {
            id: optionMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: option.picked()
        }
    }

    component Switchable: Rectangle {
        id: switchable
        property string label
        property string detail
        property bool on: false
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: switchColumn.implicitHeight + Theme.space3 * 2
        radius: Theme.radiusMd
        color: Theme.surface100
        border.color: Theme.line

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space4
            anchors.rightMargin: Theme.space4
            spacing: Theme.space4

            ColumnLayout {
                id: switchColumn
                Layout.fillWidth: true
                spacing: 2
                UiText {
                    Layout.fillWidth: true
                    text: switchable.label
                    font.weight: Font.Medium
                }
                UiText {
                    Layout.fillWidth: true
                    text: switchable.detail
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                }
            }

            ToggleSwitch {
                on: switchable.on
                onToggled: switchable.toggled()
            }
        }
    }

    Component {
        id: regionPage

        ColumnLayout {
            spacing: Theme.space2

            FieldBox {
                id: countrySearch
                Layout.fillWidth: true
                placeholder: "Search countries"
                onAccepted: root.next()
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 48
                clip: true
                contentHeight: countryList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: countryList
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.countries.filter(item => !countrySearch.text.trim() || item.name.toLowerCase().includes(countrySearch.text.trim().toLowerCase()))

                        Option {
                            required property var modelData
                            label: modelData.name
                            detail: modelData.lang
                            chosen: root.country && root.country.name === modelData.name
                            onPicked: root.country = modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: keyboardPage

        ColumnLayout {
            spacing: Theme.space2

            FieldBox {
                Layout.fillWidth: true
                placeholder: "Type here to try it: @ \" # £ € ~ | \\ / ?"
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 48
                clip: true
                contentHeight: keyboardGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: keyboardGrid
                    width: parent.width
                    columns: 2
                    columnSpacing: Theme.space2
                    rowSpacing: 2

                    Repeater {
                        model: root.keyboards

                        Option {
                            required property var modelData
                            label: modelData.label
                            chosen: root.keyboard === modelData.value
                            onPicked: root.keyboard = modelData.value
                        }
                    }
                }
            }
        }
    }

    Component {
        id: networkPage

        ColumnLayout {
            spacing: Theme.space2

            Option {
                visible: Network.wired
                glyph: "network-wired-symbolic"
                label: "Wired connection"
                detail: root.online ? "Connected" : "Connecting..."
                chosen: true
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 48
                clip: true
                contentHeight: networkList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: networkList
                    width: parent.width
                    spacing: 2

                    property string opened: ""

                    UiText {
                        visible: !Network.available && !Network.wired
                        text: "No Wi-Fi was found. Plug in a network cable."
                        color: Theme.inkMuted
                    }

                    UiText {
                        visible: Network.available && Network.networks.length === 0
                        text: "Looking for networks..."
                        color: Theme.inkMuted
                    }

                    Repeater {
                        model: Network.networks

                        ColumnLayout {
                            id: networkRow
                            required property var modelData
                            readonly property bool secure: Network.isSecure(modelData)
                            Layout.fillWidth: true
                            spacing: Theme.space1

                            Option {
                                glyph: Network.glyphFor(networkRow.modelData)
                                label: networkRow.modelData.name
                                detail: root.joining === networkRow.modelData.name ? "Connecting..." : networkRow.modelData.connected ? "Connected" : networkRow.secure ? "Secured" : "Open"
                                chosen: networkRow.modelData.connected || networkList.opened === networkRow.modelData.name
                                onPicked: {
                                    networkList.opened = networkRow.modelData.name;
                                    root.joinError = "";
                                    if (!networkRow.secure && !networkRow.modelData.connected) root.join(networkRow.modelData, "");
                                    else wifiPassword.focusField();
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: networkRow.secure && !networkRow.modelData.connected && networkList.opened === networkRow.modelData.name
                                spacing: Theme.space2

                                FieldBox {
                                    id: wifiPassword
                                    Layout.fillWidth: true
                                    password: true
                                    placeholder: "Password for " + networkRow.modelData.name
                                    onAccepted: connectButton.clicked()
                                }

                                PillButton {
                                    id: connectButton
                                    primary: true
                                    text: "Connect"
                                    enabled: wifiPassword.text.length > 0 && root.joining === ""
                                    onClicked: {
                                        root.join(networkRow.modelData, wifiPassword.text);
                                        wifiPassword.text = "";
                                    }
                                }
                            }
                        }
                    }

                    UiText {
                        visible: root.joinError.length > 0
                        text: root.joinError
                        color: Theme.danger
                    }
                }
            }
        }
    }

    Component {
        id: diskPage

        ColumnLayout {
            spacing: Theme.space2

            UiText {
                visible: root.disks.length === 0
                text: "Looking for disks..."
                color: Theme.inkMuted
            }

            Repeater {
                model: root.disks

                Option {
                    required property var modelData
                    implicitHeight: 52
                    glyph: "drive-harddisk-symbolic"
                    label: modelData.model + "  ·  " + root.gigabytes(modelData.size)
                    detail: ({ windows: "Has Windows", files: "Has files on it", empty: "Empty" })[modelData.contents] || ""
                    chosen: root.diskChosen === modelData.path
                    onPicked: {
                        root.diskChosen = modelData.path;
                        root.eraseAgreed = false;
                    }
                }
            }

            Switchable {
                Layout.topMargin: Theme.space3
                visible: root.disk !== null
                label: "Erase " + (root.disk ? root.disk.model : "") + " and install Graphite Desk"
                detail: "Everything on it goes, for good. Copy anything you want to keep first."
                on: root.eraseAgreed
                onToggled: root.eraseAgreed = !root.eraseAgreed
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: accountPage

        ColumnLayout {
            spacing: Theme.space2

            UiText {
                text: "Your name"
                font.weight: Font.Medium
                font.pixelSize: Theme.actionSize
            }

            FieldBox {
                Layout.fillWidth: true
                placeholder: "Joe"
                onAccepted: root.next()
                text: fullName.text
                onTextChanged: fullName.text = text
                Component.onCompleted: focusField()
                border.color: root.triedAccount && !fullName.text.trim() ? Theme.danger : Theme.line
            }

            UiText {
                visible: fullName.text.trim().length > 0
                text: "You'll sign in as " + root.userName + "; this PC is called " + root.hostName
                color: Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            UiText {
                Layout.topMargin: Theme.space2
                text: "Password"
                font.weight: Font.Medium
                font.pixelSize: Theme.actionSize
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2

                FieldBox {
                    Layout.fillWidth: true
                    placeholder: "At least 8 characters"
                    onAccepted: root.next()
                    password: !root.showPassword
                    text: secret.text
                    onTextChanged: secret.text = text
                    border.color: secret.text.length && secret.text.length < 8 ? Theme.danger : Theme.line
                }

                BarButton {
                    glyph: root.showPassword ? "view-conceal-symbolic" : "view-reveal-symbolic"
                    onClicked: root.showPassword = !root.showPassword
                }
            }

            // How strong it is: four bars.
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space1

                Repeater {
                    model: 4

                    Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 2
                        color: index < root.strength ? (root.strength <= 1 ? Theme.danger : root.strength === 2 ? Theme.accent : Theme.success) : Theme.surface300
                    }
                }
            }

            UiText {
                text: secret.text.length === 0 ? "" : secret.text.length < 8 ? "Passwords need at least 8 characters" : ["", "Weak password", "Okay password", "Good password", "Strong password"][root.strength]
                color: secret.text.length < 8 ? Theme.danger : Theme.inkMuted
                font.pixelSize: Theme.hintSize
            }

            UiText {
                Layout.topMargin: Theme.space2
                text: "PIN for signing in quickly (optional)"
                font.weight: Font.Medium
                font.pixelSize: Theme.actionSize
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space3

                FieldBox {
                    Layout.preferredWidth: 140
                    placeholder: "4 digits"
                    password: !root.showPassword
                    text: pinStore.text
                    onTextChanged: pinStore.text = text.replace(/[^0-9]/g, "").slice(0, 4)
                    onAccepted: root.next()
                    border.color: pinStore.text.length && pinStore.text.length < 4 ? Theme.danger : Theme.line
                }

                UiText {
                    Layout.fillWidth: true
                    text: pinStore.text.length && pinStore.text.length < 4 ? "A PIN is 4 digits" : "Sign in with it instead of the password, as on Windows"
                    color: pinStore.text.length && pinStore.text.length < 4 ? Theme.danger : Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            UiText {
                Layout.topMargin: Theme.space2
                text: "Password hint (optional)"
                font.weight: Font.Medium
                font.pixelSize: Theme.actionSize
            }

            FieldBox {
                Layout.fillWidth: true
                placeholder: "Shown after three wrong tries; not the password itself"
                onAccepted: root.next()
                text: hintStore.text
                onTextChanged: hintStore.text = text
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: privacyPage

        ColumnLayout {
            spacing: Theme.space2

            Switchable {
                label: "Encrypt the disk"
                detail: "Without your password, nobody can read the disk, even if it's taken out. You type the password when the PC starts."
                on: root.encrypt
                onToggled: root.encrypt = !root.encrypt
            }

            Switchable {
                label: "Firewall"
                detail: "Nothing from the network can reach this PC unless it asked. Always on; it can be changed in the Control Panel."
                on: root.firewall
                onToggled: root.firewall = true
            }

            Switchable {
                label: "Install updates automatically"
                detail: "Once a day, in the background, so this PC stays safe without you thinking about it."
                on: root.autoUpdates
                onToggled: root.autoUpdates = !root.autoUpdates
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: lookPage

        ColumnLayout {
            spacing: Theme.space3

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space3

                Repeater {
                    model: [
                        { value: "dark", label: "Dark", back: "#232427", front: "#3b3c40" },
                        { value: "light", label: "Light", back: "#e7e5e1", front: "#ffffff" },
                        { value: "auto", label: "Match time of day", back: "#232427", front: "#ffffff" }
                    ]

                    Rectangle {
                        id: lookCard
                        required property var modelData
                        readonly property bool chosen: root.theme === modelData.value
                        Layout.fillWidth: true
                        implicitHeight: 120
                        radius: Theme.radiusMd
                        color: Theme.surface100
                        border.color: chosen ? Theme.accent : Theme.line
                        border.width: chosen ? 2 : 1

                        Rectangle {
                            x: Theme.space2
                            y: Theme.space2
                            width: parent.width - Theme.space2 * 2
                            height: 72
                            radius: Theme.radiusSm
                            color: lookCard.modelData.back
                            clip: true

                            Rectangle {
                                x: lookCard.modelData.value === "auto" ? parent.width / 2 : 14
                                y: 14
                                width: lookCard.modelData.value === "auto" ? parent.width / 2 - 14 : parent.width - 28
                                height: parent.height - 14
                                radius: 4
                                color: lookCard.modelData.front
                            }
                        }

                        UiText {
                            x: Theme.space3
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Theme.space3
                            text: lookCard.modelData.label
                            font.weight: lookCard.chosen ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.theme = lookCard.modelData.value
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    Component {
        id: appsPage

        ColumnLayout {
            spacing: Theme.space2

            Switchable {
                label: "Set up for games"
                detail: "Steam, Minecraft (the Modrinth App), your graphics drivers, GameMode and an FPS counter"
                on: root.gaming
                onToggled: root.gaming = !root.gaming
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.bottomMargin: 48
                clip: true
                contentHeight: appGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                GridLayout {
                    id: appGrid
                    width: parent.width
                    columns: 2
                    columnSpacing: Theme.space2
                    rowSpacing: Theme.space2

                    Repeater {
                        model: root.appChoices

                        Rectangle {
                            id: appCard
                            required property var modelData
                            readonly property bool chosen: root.apps.includes(modelData.id)
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Theme.radiusSm
                            color: chosen ? Theme.surface300 : appMouse.containsMouse ? Theme.surface300 : Theme.surface100
                            border.color: chosen ? Theme.lineStrong : Theme.line
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space3
                                anchors.rightMargin: Theme.space3
                                spacing: Theme.space3

                                Rectangle {
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    radius: Theme.radiusSm
                                    color: Theme.surface200
                                    border.color: Theme.line

                                    UiText {
                                        anchors.centerIn: parent
                                        text: appCard.modelData.name.slice(0, 1)
                                        font.weight: Font.DemiBold
                                        font.pixelSize: Theme.hintSize
                                    }
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    text: appCard.modelData.name
                                }

                                Rectangle {
                                    implicitWidth: 6
                                    implicitHeight: 6
                                    radius: 3
                                    color: root.tagColour(appCard.modelData.tag)
                                }

                                UiText {
                                    text: appCard.modelData.tag
                                    color: Theme.inkMuted
                                    font.pixelSize: Theme.hintSize
                                }

                                // The tick box.
                                Rectangle {
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    radius: 4
                                    color: appCard.chosen ? Theme.ink : "transparent"
                                    border.color: appCard.chosen ? Theme.ink : Theme.lineStrong
                                    border.width: 1.5

                                    UiText {
                                        visible: appCard.chosen
                                        anchors.centerIn: parent
                                        text: "✓"
                                        color: Theme.surface200
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            MouseArea {
                                id: appMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: root.toggleApp(appCard.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: installingPage

        ColumnLayout {
            spacing: Theme.space2

            Repeater {
                model: root.stages

                RowLayout {
                    id: stageRow
                    required property var modelData
                    readonly property bool done: root.stagesDone.includes(modelData.id)
                    readonly property bool current: root.stageNow === modelData.id
                    spacing: Theme.space3

                    Item {
                        implicitWidth: 16
                        implicitHeight: 16

                        UiText {
                            anchors.centerIn: parent
                            visible: stageRow.done
                            text: "✓"
                            color: Theme.success
                            font.weight: Font.Bold
                        }

                        // The one going now: a turning arc.
                        Rectangle {
                            anchors.fill: parent
                            visible: stageRow.current && !root.failed
                            radius: 8
                            color: "transparent"
                            border.color: Theme.accent
                            border.width: 2

                            Rectangle {
                                width: 8
                                height: 8
                                color: Theme.surface200
                            }

                            RotationAnimation on rotation {
                                running: stageRow.current
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 900
                            }
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: !stageRow.done && !stageRow.current
                            width: 12
                            height: 12
                            radius: 6
                            color: "transparent"
                            border.color: Theme.lineStrong
                        }
                    }

                    UiText {
                        Layout.fillWidth: true
                        text: stageRow.modelData.name
                        color: stageRow.done || stageRow.current ? Theme.ink : Theme.inkMuted
                    }

                    UiText {
                        visible: stageRow.current
                        text: root.percent + "%"
                        color: Theme.inkMuted
                        font.pixelSize: Theme.hintSize
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space4
                implicitHeight: 4
                radius: 2
                color: Theme.surface300

                Rectangle {
                    width: parent.width * root.percent / 100
                    height: parent.height
                    radius: 2
                    color: root.failed ? Theme.danger : Theme.ink
                    Behavior on width { NumberAnimation { duration: 400 } }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                UiText {
                    Layout.fillWidth: true
                    text: root.stepText
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
                UiText {
                    text: "About " + root.installMinutesLeft + " minutes left"
                    color: Theme.inkMuted
                    font.pixelSize: Theme.hintSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space3
                visible: !root.failed
                implicitHeight: tipText.implicitHeight + Theme.space3 * 2
                radius: Theme.radiusMd
                color: Theme.surface100
                border.color: Theme.line

                UiText {
                    id: tipText
                    x: Theme.space4
                    width: parent.width - Theme.space4 * 2
                    anchors.verticalCenter: parent.verticalCenter
                    wrapMode: Text.WordWrap
                    text: "Tip: " + root.tips[root.tip]
                    color: Theme.inkMuted
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.failed
                wrapMode: Text.WordWrap
                text: "The details are in /tmp/graphite-install.log. Try again, or go Back to change your choices."
                color: Theme.inkMuted
            }

            Item { Layout.fillHeight: true }
        }
    }
}
