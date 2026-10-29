pragma Singleton
// The desktop beyond the shell: the apps' look (linux/gtk/apply.sh) and the text setting, the
// app installer's registration (linux/apps), the app store, the gaming setup, and which apps
// can be uninstalled from the launcher (those the installer put there, and Flatpak apps).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string linux: Quickshell.shellDir + "/.."
    readonly property bool smoothText: !ShellSettings.values || ShellSettings.values.smoothText !== false

    // Where each app came from, by desktop entry id: "flatpak", "deb" (the Ubuntu space),
    // "appimage", "pacman" (installed by file); anything else is a system package.
    property var sources: ({})
    // The desktop's own parts, never offered for uninstalling.
    readonly property var essential: ["kitty", "org.gnome.Nautilus", "org.gnome.Software", "graphite-install"]

    function sourceOf(id) {
        return sources[String(id).replace(/\.desktop$/, "")] || "system";
    }

    function sourceLabel(id) {
        return ({ flatpak: "Flatpak", deb: "Ubuntu app", appimage: "AppImage", pacman: "Package", system: "System" })[sourceOf(id)];
    }

    // Apps a newcomer is likely to want, one click each from Flathub.
    readonly property var featured: [
        { id: "app.zen_browser.zen", name: "Zen Browser", detail: "A calm, private web browser" },
        { id: "com.valvesoftware.Steam", name: "Steam", detail: "Games, with Proton for Windows games" },
        { id: "net.lutris.Lutris", name: "Lutris", detail: "Battle.net, EA, Ubisoft and more games" },
        { id: "io.bassi.Amberol", name: "Amberol", detail: "Plays your music" },
        { id: "org.gnome.gThumb", name: "gThumb", detail: "Browse and edit photos" },
        { id: "org.gnome.Shotwell", name: "Shotwell", detail: "Your photo library" },
        { id: "com.discordapp.Discord", name: "Discord", detail: "Chat, voice and video" },
        { id: "com.spotify.Client", name: "Spotify", detail: "Music" },
        { id: "org.videolan.VLC", name: "VLC", detail: "Plays any video" },
        { id: "com.obsproject.Studio", name: "OBS Studio", detail: "Record and stream" },
        { id: "com.visualstudio.code", name: "Visual Studio Code", detail: "Code editor" },
        { id: "org.libreoffice.LibreOffice", name: "LibreOffice", detail: "Documents and spreadsheets" },
        { id: "org.gimp.GIMP", name: "GIMP", detail: "Photo editing" },
        { id: "org.telegram.desktop", name: "Telegram", detail: "Messaging" },
        { id: "com.google.Chrome", name: "Google Chrome", detail: "Web browser" },
        { id: "com.modrinth.ModrinthApp", name: "Modrinth App", detail: "Minecraft and modpacks" },
        { id: "com.heroicgameslauncher.hgl", name: "Heroic", detail: "Epic and GOG games" },
        { id: "org.blender.Blender", name: "Blender", detail: "3D" }
    ]

    // Flathub ids being installed now, and installed (from `flatpak list`).
    property var installing: ({})
    property var flatpaks: ({})

    function isInstalled(appId) {
        return flatpaks[appId] === true;
    }

    function install(appId) {
        const busy = Object.assign({}, installing);
        busy[appId] = true;
        installing = busy;
        Quickshell.execDetached(["bash", linux + "/apps/install-app.sh", "--flathub", appId]);
    }

    // Flathub's answers for a search: [{ id, name, detail }].
    property var results: []
    property bool searching: false

    function search(text) {
        const query = text.trim();
        if (!query) {
            results = [];
            packages = [];
            return;
        }
        searching = true;
        finder.command = ["flatpak", "search", "--columns=application,name,description", query];
        finder.running = true;
        packageFinder.query = query.toLowerCase();
        packageFinder.command = ["pacman", "-Ss", "--", query];
        packageFinder.running = true;
    }

    // Arch Linux's own packages for the same search (from its main and 32-bit repositories,
    // the ones whose name has the words first): [{ name, detail, installed }].
    property var packages: []
    property var installingPackages: ({})

    Process {
        id: packageFinder
        property string query
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                const found = [];
                for (let index = 0; index < lines.length; index++) {
                    const match = /^(extra|multilib)\/(\S+) \S+(.*)$/.exec(lines[index]);
                    if (!match) continue;
                    // Apps, not their parts: no help or language files, libraries or add-ons.
                    if (/-(help|doc|docs|devel|headers|lang|l10n|i18n|plugin|plugins|data)(-|$)/.test(match[2])) continue;
                    if (/^(lib|python-|perl-|ruby-|haskell-|nodejs-|lua-|php-|java-|rust-|go-)/.test(match[2])) continue;
                    found.push({ name: match[2], detail: (lines[index + 1] || "").trim(), installed: match[3].includes("[installed") });
                }
                const words = packageFinder.query.split(/\s+/);
                const named = found.filter(item => words.every(word => item.name.includes(word)));
                root.packages = named.concat(found.filter(item => !named.includes(item))).slice(0, 6);
            }
        }
    }

    function installPackage(name) {
        const busy = Object.assign({}, installingPackages);
        busy[name] = true;
        installingPackages = busy;
        Quickshell.execDetached(["sh", "-c", `bash "$1" --package "$2"; qs -c graphite ipc call taskbar rebuild >/dev/null 2>&1`, "sh", linux + "/apps/install-app.sh", name]);
        packageCheck.restart();
    }

    // Which of the packages being installed are in now.
    Process {
        id: packageInstalled
        stdout: StdioCollector {
            onStreamFinished: {
                const done = this.text.split("\n").filter(line => line);
                const busy = {};
                for (const name of Object.keys(root.installingPackages)) if (!done.includes(name)) busy[name] = true;
                root.installingPackages = busy;
                root.packages = root.packages.map(item => Object.assign({}, item, { installed: item.installed || done.includes(item.name) }));
            }
        }
    }
    Timer {
        id: packageCheck
        interval: 4000
        repeat: true
        running: Object.keys(root.installingPackages).length > 0
        onTriggered: {
            packageInstalled.command = ["sh", "-c", "pacman -Qq \"$@\" 2>/dev/null", "sh"].concat(Object.keys(root.installingPackages));
            packageInstalled.running = true;
        }
    }

    // Not in either: the web, for the app's own download (a .deb or an AppImage installs itself
    // when opened, and Downloads is watched below).
    function searchWeb(text) {
        Quickshell.execDetached(["xdg-open", "https://duckduckgo.com/?q=" + encodeURIComponent(text.trim() + " download for Linux (.deb OR AppImage)")]);
    }

    // A finished download that's an app: a notification offers to install it (a click on it does).
    property double downloadsChecked: Date.now() / 1000

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: if (!downloads.running) downloads.running = true
    }

    Process {
        id: downloads
        command: ["sh", "-c", `find "$HOME/Downloads" -maxdepth 1 -type f -newerct @${Math.floor(root.downloadsChecked)} \\( -iname '*.deb' -o -iname '*.appimage' -o -iname '*.flatpakref' -o -iname '*.pkg.tar.zst' \\) 2>/dev/null`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.downloadsChecked = Date.now() / 1000 - 1;
                for (const file of this.text.split("\n").filter(line => line)) {
                    const base = file.split("/").pop();
                    Quickshell.execDetached(["sh", "-c",
                        `[ "$(notify-send -a 'Graphite Desk' -i system-software-install --action=default=Install --wait "Install $2?" "It finished downloading. Click here to install it.")" = default ] && bash "$3" "$1"`,
                        "sh", file, base, root.linux + "/apps/install-app.sh"]);
                }
            }
        }
    }

    Process {
        id: finder
        stdout: StdioCollector {
            onStreamFinished: {
                root.searching = false;
                const seen = {};
                root.results = this.text.split("\n").map(line => line.split("\t")).filter(parts => parts.length >= 2 && parts[0].includes(".")).filter(parts => {
                    if (seen[parts[0]]) return false;
                    seen[parts[0]] = true;
                    return true;
                }).slice(0, 40).map(parts => ({ id: parts[0].trim(), name: (parts[1] || parts[0]).trim(), detail: (parts[2] || "").trim() }));
            }
        }
    }

    function applyLook(dark) {
        Quickshell.execDetached(["bash", linux + "/gtk/apply.sh", dark ? "dark" : "light"]);
    }

    function register() {
        Quickshell.execDetached(["bash", linux + "/apps/register.sh"]);
    }

    // On, FreeType's stem darkening (hyprland.lua reads the choice) for apps opened from now on.
    function setSmoothText(on) {
        ShellSettings.set("smoothText", on);
        Quickshell.execDetached(["sh", "-c", `mkdir -p "$HOME/.config/graphite" && printf ${on ? "smooth" : "standard"} > "$HOME/.config/graphite/text" && hyprctl reload`]);
    }

    // The Apps window (AppsWindow.qml), on its "Get apps" page.
    function openAppStore() {
        ShellState.appsPage = "get";
        ShellState.appsOpen = true;
    }

    function openApps() {
        ShellState.appsPage = "installed";
        ShellState.appsOpen = true;
    }

    // The system, the apps and Graphite Desk itself, on the Control Panel's Updates page.
    function updateEverything() {
        ShellState.openSettings("updates");
        Updates.install();
    }

    // In the background: the password once (pkexec's window), then notifications as it goes.
    function setUpGaming() {
        Quickshell.execDetached(["sh", "-c", [
            "notify-send -a 'Graphite Desk' -i applications-games 'Setting up gaming' 'Steam, Minecraft and your graphics drivers are on their way. This takes a few minutes.'",
            `if pkexec env GRAPHITE_USER="$USER" bash "${linux}/gaming.sh" --background > /tmp/graphite-gaming.log 2>&1; then`,
            "  notify-send -a 'Graphite Desk' -i applications-games 'Gaming is ready' 'Steam and the Modrinth App are in your apps. If it says so in the log, restart for new drivers.'",
            "else",
            "  notify-send -a 'Graphite Desk' -i dialog-warning 'Gaming setup didn'\\''t finish' 'Try again from the Control Panel (Apps). Details: /tmp/graphite-gaming.log'",
            "fi"
        ].join("\n")]);
    }

    function canRemove(id) {
        return !essential.includes(String(id).replace(/\.desktop$/, ""));
    }

    function uninstall(id) {
        Quickshell.execDetached(["bash", linux + "/apps/install-app.sh", "--remove", String(id).replace(/\.desktop$/, "")]);
        refreshSoon.restart();
    }

    function refresh() {
        listing.running = true;
    }

    // "kind id" per line: the installer's records, then the Flatpak apps.
    Process {
        id: listing
        command: ["sh", "-c", "for f in \"$HOME/.local/share/graphite/apps\"/*; do [ -f \"$f\" ] && echo \"$(sed -n 's/^kind=//p' \"$f\") $(basename \"$f\")\"; done; flatpak list --app --columns=application 2>/dev/null | sed 's/^/flatpak /'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const sources = {};
                const flatpaks = {};
                for (const line of this.text.split("\n")) {
                    const [kind, id] = line.trim().split(" ");
                    if (!kind || !id) continue;
                    sources[id] = kind;
                    if (kind === "flatpak") flatpaks[id] = true;
                }
                root.sources = sources;
                root.flatpaks = flatpaks;
                // Installs that have finished leave the busy list.
                const busy = {};
                for (const id of Object.keys(root.installing)) if (!flatpaks[id]) busy[id] = true;
                root.installing = busy;
            }
        }
    }

    Timer {
        id: refreshSoon
        interval: 4000
        onTriggered: root.refresh()
    }

    // While something installs, check every few seconds for it to finish.
    Timer {
        interval: 4000
        repeat: true
        running: Object.keys(root.installing).length > 0
        onTriggered: root.refresh()
    }

    // New installs show up within a minute even when installed from elsewhere.
    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
