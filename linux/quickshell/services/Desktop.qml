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
        { id: "com.discordapp.Discord", name: "Discord", detail: "Chat, voice and video" },
        { id: "com.spotify.Client", name: "Spotify", detail: "Music" },
        { id: "org.videolan.VLC", name: "VLC", detail: "Plays any video" },
        { id: "com.obsproject.Studio", name: "OBS Studio", detail: "Record and stream" },
        { id: "com.visualstudio.code", name: "Visual Studio Code", detail: "Code editor" },
        { id: "org.libreoffice.LibreOffice", name: "LibreOffice", detail: "Documents and spreadsheets" },
        { id: "org.gimp.GIMP", name: "GIMP", detail: "Photo editing" },
        { id: "org.telegram.desktop", name: "Telegram", detail: "Messaging" },
        { id: "com.google.Chrome", name: "Google Chrome", detail: "Web browser" },
        { id: "org.prismlauncher.PrismLauncher", name: "Prism Launcher", detail: "Minecraft and modpacks" },
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
            return;
        }
        searching = true;
        finder.command = ["flatpak", "search", "--columns=application,name,description", query];
        finder.running = true;
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

    // The system, the apps and Graphite Desk itself (linux/update.sh), in a terminal.
    function updateEverything() {
        Quickshell.execDetached(["kitty", "--title", "Updating everything", "bash", linux + "/update.sh"]);
    }

    // In a terminal, as it asks for the password and reports what it does.
    function setUpGaming() {
        Quickshell.execDetached(["kitty", "--title", "Setting up gaming", "bash", linux + "/gaming.sh"]);
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
