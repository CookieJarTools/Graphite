pragma Singleton
// The desktop beyond the shell: the apps' look (linux/gtk/apply.sh) and the text setting, the
// app installer's registration (linux/apps), the app store (Arch, Flathub and GitHub), the
// gaming setup, and which apps can be uninstalled from the launcher (those the installer put
// there, and Flatpak apps).

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property string linux: Quickshell.shellDir + "/.."
    readonly property bool smoothText: !ShellSettings.values || ShellSettings.values.smoothText !== false

    // Where each app came from, by desktop entry id: "flatpak", "deb" (the Ubuntu space),
    // "appimage", "pacman" (installed by file), "vendor" (from its maker, vendorFor); anything
    // else is a system package.
    property var sources: ({})
    // The desktop's own parts, never offered for uninstalling.
    readonly property var essential: ["kitty", "org.gnome.Nautilus", "org.gnome.Software", "graphite-install"]

    function sourceOf(id) {
        return sources[String(id).replace(/\.desktop$/, "")] || "system";
    }

    function sourceLabel(id) {
        const source = sourceOf(id);
        if (source === "vendor") {
            const made = Object.values(vendorFor).find(app => app.id === String(id).replace(/\.desktop$/, ""));
            return made ? made.maker : "Its maker";
        }
        return ({ flatpak: "Flathub", deb: "Ubuntu app", appimage: "AppImage", archive: "Downloaded app", pacman: "Arch Linux", system: "System" })[source];
    }

    // Apps Arch Linux packages itself, by their Flathub id. These come from Arch: they use the
    // system's own libraries and graphics driver, so they open faster and update with everything
    // else. Steam comes through the gaming setup (it needs 32-bit drivers too).
    readonly property var archFor: ({
        "com.discordapp.Discord": "discord",
        "org.telegram.desktop": "telegram-desktop",
        "org.videolan.VLC": "vlc",
        "org.libreoffice.LibreOffice": "libreoffice-fresh",
        "com.obsproject.Studio": "obs-studio",
        "org.gimp.GIMP": "gimp",
        "org.blender.Blender": "blender",
        "net.lutris.Lutris": "lutris",
        "org.gnome.gThumb": "gthumb",
        "org.gnome.Shotwell": "shotwell",
        "io.bassi.Amberol": "amberol",
        "com.modrinth.ModrinthApp": "modrinth-app",
        "com.spotify.Client": "spotify-launcher",
        "org.mozilla.firefox": "firefox",
        "org.mozilla.Thunderbird": "thunderbird",
        "org.chromium.Chromium": "chromium",
        "org.kde.krita": "krita",
        "org.inkscape.Inkscape": "inkscape",
        "org.audacityteam.Audacity": "audacity",
        "org.kde.kdenlive": "kdenlive",
        "io.mpv.Mpv": "mpv",
        "io.github.celluloid_player.Celluloid": "celluloid",
        "fr.handbrake.ghb": "handbrake",
        "org.qbittorrent.qBittorrent": "qbittorrent",
        "org.signal.Signal": "signal-desktop",
        "im.riot.Riot": "element-desktop",
        "org.keepassxc.KeePassXC": "keepassxc",
        "org.remmina.Remmina": "remmina",
        "org.gnome.Rhythmbox3": "rhythmbox",
        "org.prismlauncher.PrismLauncher": "prismlauncher",
        "com.transmissionbt.Transmission": "transmission-gtk"
    })

    // Apps their makers publish for Linux themselves, by their Flathub id, where Flathub's copy
    // doesn't do the job: installed from the maker, for the person (apps/install-app.sh
    // --vendor), and updated with everything else. id is the desktop entry it gets, and the
    // Arch package name that counts as having it too (from the AUR, say).
    //   Unity Hub: from Flathub, Unity runs in a sandbox where a game that uses Steam can't
    //   reach Steam, and closes when Play is pressed.
    readonly property var vendorFor: ({
        "com.unity.UnityHub": { id: "unityhub", maker: "Unity" }
    })

    // Arch's packages from archFor (and vendorFor) that are installed (pacman -Qq), and whether
    // Steam is.
    property var archInstalled: ({})

    // Apps a newcomer is likely to want, one click each: from Arch when it has them, else Flathub.
    readonly property var featured: [
        { id: "app.zen_browser.zen", name: "Zen Browser", detail: "Private web browser" },
        { id: "com.valvesoftware.Steam", name: "Steam", detail: "Games, including many Windows games" },
        { id: "net.lutris.Lutris", name: "Lutris", detail: "Games from Battle.net, EA, Ubisoft and more" },
        { id: "io.bassi.Amberol", name: "Amberol", detail: "Music player" },
        { id: "org.gnome.gThumb", name: "gThumb", detail: "Browse and edit photos" },
        { id: "org.gnome.Shotwell", name: "Shotwell", detail: "Photo library" },
        { id: "com.discordapp.Discord", name: "Discord", detail: "Chat, voice and video" },
        { id: "com.spotify.Client", name: "Spotify", detail: "Music" },
        { id: "org.videolan.VLC", name: "VLC", detail: "Video player" },
        { id: "com.obsproject.Studio", name: "OBS Studio", detail: "Record and stream" },
        { id: "com.visualstudio.code", name: "Visual Studio Code", detail: "Code editor" },
        { id: "org.libreoffice.LibreOffice", name: "LibreOffice", detail: "Documents and spreadsheets" },
        { id: "org.gimp.GIMP", name: "GIMP", detail: "Photo editing" },
        { id: "org.telegram.desktop", name: "Telegram", detail: "Messaging" },
        { id: "com.google.Chrome", name: "Google Chrome", detail: "Web browser" },
        { id: "com.modrinth.ModrinthApp", name: "Modrinth App", detail: "Minecraft and modpacks" },
        { id: "com.heroicgameslauncher.hgl", name: "Heroic", detail: "Epic and GOG games" },
        { id: "org.blender.Blender", name: "Blender", detail: "3D modelling" }
    ]

    // Flathub ids being installed now, and installed (from `flatpak list`).
    property var installing: ({})
    property var flatpaks: ({})

    function isInstalled(appId) {
        if (appId === "com.valvesoftware.Steam") return archInstalled["steam"] === true || flatpaks[appId] === true;
        return flatpaks[appId] === true || nativeInstalled(appId);
    }

    // Installed other than from Flathub: from Arch, or from its maker.
    function nativeInstalled(appId) {
        if (archFor[appId] !== undefined) return archInstalled[archFor[appId]] === true;
        const app = vendorFor[appId];
        return app !== undefined && (sources[app.id] === "vendor" || archInstalled[app.id] === true);
    }

    // Where an app comes from, for its row: "Arch Linux", its maker, or "Flathub".
    function originOf(appId) {
        if (vendorFor[appId] !== undefined) return vendorFor[appId].maker;
        return archFor[appId] !== undefined || appId === "com.valvesoftware.Steam" ? "Arch Linux" : "Flathub";
    }

    function install(appId) {
        const busy = Object.assign({}, installing);
        busy[appId] = Date.now();
        installing = busy;
        if (appId === "com.valvesoftware.Steam") {
            setUpGaming();
        } else if (archFor[appId] !== undefined) {
            Quickshell.execDetached(["sh", "-c", `bash "$1" --package "$2"; qs -c graphite ipc call taskbar rebuild >/dev/null 2>&1`, "sh", linux + "/apps/install-app.sh", archFor[appId]]);
            refreshSoon.restart();
        } else if (vendorFor[appId] !== undefined) {
            Quickshell.execDetached(["sh", "-c", `bash "$1" --vendor "$2"; qs -c graphite ipc call taskbar rebuild >/dev/null 2>&1`, "sh", linux + "/apps/install-app.sh", vendorFor[appId].id]);
            refreshSoon.restart();
        } else {
            Quickshell.execDetached(["bash", linux + "/apps/install-app.sh", "--flathub", appId]);
        }
    }

    // A Flathub app that Arch also has, or its maker: that copy goes in, then the Flathub one
    // comes out.
    function canSwitch(appId) {
        return (archFor[appId] !== undefined || vendorFor[appId] !== undefined) && flatpaks[appId] === true && !nativeInstalled(appId);
    }

    function switchLabel(appId) {
        return vendorFor[appId] !== undefined ? "Use " + vendorFor[appId].maker + "'s version" : "Use Arch's version";
    }

    function switchToNative(appId) {
        const busy = Object.assign({}, installing);
        busy[appId] = Date.now();
        installing = busy;
        const how = vendorFor[appId] !== undefined ? ["--vendor", vendorFor[appId].id] : ["--package", archFor[appId]];
        Quickshell.execDetached(["sh", "-c", `bash "$1" "$2" "$3" --replaces "$4"; qs -c graphite ipc call taskbar rebuild >/dev/null 2>&1`, "sh", linux + "/apps/install-app.sh"].concat(how, [appId]));
        refreshSoon.restart();
    }

    // Flathub's answers for a search: [{ id, name, detail }].
    property var results: []
    property bool searching: false

    function search(text) {
        const query = text.trim();
        searchGithub(query);
        // A GitHub link is looked up on GitHub alone.
        if (!query || githubRepo(query)) {
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

    // Which of the packages being installed are in now, and which installs ended without them
    // (the password cancelled, or offline: install-app.sh says why), so none waits forever.
    Process {
        id: packageInstalled
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(line => line);
                const done = lines.filter(line => !line.startsWith("ended "));
                const ended = lines.filter(line => line.startsWith("ended ")).map(line => line.slice(6));
                const busy = {};
                for (const name of Object.keys(root.installingPackages)) if (!done.includes(name) && !ended.includes(name)) busy[name] = true;
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
            // The installs still going first, so one ending in between is seen as in.
            packageInstalled.command = ["sh", "-c", "for name; do pgrep -f \"install-app\\.sh --package $(printf %s \"$name\" | sed 's/[.+]/\\\\&/g')( |\\$)\" >/dev/null || echo \"ended $name\"; done; pacman -Qq \"$@\" 2>/dev/null", "sh"].concat(Object.keys(root.installingPackages));
            packageInstalled.running = true;
        }
    }

    // ---------- GitHub (apps/github.sh) ----------

    // A project's link or "owner/repo" in the search: that project, looked up at once; other
    // words: GitHub's most starred matches. [{ repo, owner, name, description, stars, url }]
    property var githubResults: []
    property bool githubSearching: false
    property string githubQuery: ""
    // By "owner/repo": what installing it would do (github.sh find's answer), whether that's
    // being looked up or installed, that it's in, or what went wrong, in plain words.
    property var githubDetails: ({})
    property var githubChecking: ({})
    property var githubInstalling: ({})
    property var githubDone: ({})
    property var githubErrors: ({})

    function githubRepo(text) {
        const match = /^(?:https?:\/\/)?(?:www\.)?(?:github\.com\/)?([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+?)(?:\.git)?(?:[\/#?].*)?$/.exec(text.trim());
        if (!match || (!/github\.com/.test(text) && /\s/.test(text.trim()))) return "";
        return match[1] + "/" + match[2];
    }

    function searchGithub(query) {
        githubQuery = query;
        githubErrors = Object.assign({}, githubErrors, { "": "" });
        const repo = githubRepo(query);
        if (repo) {
            githubResults = githubDetails[repo] ? [githubDetails[repo]] : [];
            githubCheck(repo, true);
            return;
        }
        githubResults = [];
        if (query.length < 3) return;
        githubSearching = true;
        githubRun(["search"].concat(query.split(/\s+/)), (code, out, said) => {
            if (query !== root.githubQuery) return;
            root.githubSearching = false;
            try {
                root.githubResults = code === 0 ? JSON.parse(out) : [];
            } catch (error) {
                root.githubResults = [];
            }
            root.githubErrors = Object.assign({}, root.githubErrors, { "": code === 0 ? "" : said });
        });
    }

    function githubCheck(repo, asResult) {
        githubChecking = Object.assign({}, githubChecking, { [repo]: true });
        githubRun(["find", repo], (code, out, said) => {
            const checking = Object.assign({}, root.githubChecking);
            delete checking[repo];
            root.githubChecking = checking;
            root.githubSearching = false;
            if (code !== 0) {
                root.githubErrors = Object.assign({}, root.githubErrors, { [repo]: said || "GitHub couldn't be reached." });
                if (asResult) root.githubErrors = Object.assign({}, root.githubErrors, { "": said });
                return;
            }
            try {
                const found = JSON.parse(out);
                root.githubDetails = Object.assign({}, root.githubDetails, { [repo]: found });
                if (asResult && root.githubRepo(root.githubQuery) === repo) root.githubResults = [found];
            } catch (error) {
                // an answer cut short: Check can be pressed again
            }
        });
        if (asResult) githubSearching = true;
    }

    function githubInstall(repo) {
        githubInstalling = Object.assign({}, githubInstalling, { [repo]: true });
        const errors = Object.assign({}, githubErrors);
        delete errors[repo];
        githubErrors = errors;
        githubRun(["install", repo], (code, out, said) => {
            const busy = Object.assign({}, root.githubInstalling);
            delete busy[repo];
            root.githubInstalling = busy;
            if (code === 0) root.githubDone = Object.assign({}, root.githubDone, { [repo]: true });
            else root.githubErrors = Object.assign({}, root.githubErrors, { [repo]: said || "It couldn't be installed." });
            Quickshell.execDetached(["qs", "-c", "graphite", "ipc", "call", "taskbar", "rebuild"]);
            root.refresh();
        });
    }

    // What installing a project would do, for its row: where from, and which file.
    function githubPlan(found) {
        const choice = found.choice;
        if (!choice) return found.reason;
        if (choice.kind === "arch") return "Installs " + choice.package + " from Arch Linux, which keeps it up to date";
        if (choice.kind === "flathub") return "Installs it from Flathub, which keeps it up to date";
        return "Installs " + choice.file + " (" + Machine.size(choice.size) + ") from " + found.owner + " on GitHub";
    }

    Component {
        id: githubJob

        Process {
            id: job
            property var finished: null
            stdout: StdioCollector { id: jobOut }
            stderr: StdioCollector { id: jobSaid }
            onExited: code => {
                if (job.finished) job.finished(code, jobOut.text, jobSaid.text.trim().split("\n").pop());
                job.destroy();
            }
        }
    }

    function githubRun(args, finished) {
        const job = githubJob.createObject(root, { command: ["bash", linux + "/apps/github.sh"].concat(args), finished: finished });
        job.running = true;
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
                        `[ "$(notify-send -a 'Graphite' -i system-software-install --action=default=Install --wait "Install $2?" "Download finished. Click to install it.")" = default ] && bash "$3" "$1"`,
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

    // The apps' colours (gtk/apply.sh): the scheme, and the shell's accent, worked out here for
    // that scheme (Theme may not have changed over to it yet): its fill, its text colour, the
    // words on the fill, and the terminal's selection (the accent at 30% over its background).
    function applyLook(dark) {
        const accent = Theme.accentSet;
        const text = dark ? accent.text : Qt.darker(accent.fill, 1.25).toString();
        const selection = Qt.tint("#0b0c0e", "#4d" + accent.accent.slice(1)).toString();
        Quickshell.execDetached(["bash", linux + "/gtk/apply.sh", dark ? "dark" : "light", accent.fill, text, accent.onFill, selection]);
    }

    function register() {
        Quickshell.execDetached(["bash", linux + "/apps/register.sh"]);
    }

    // On, FreeType's stem darkening (hyprland.lua reads the choice) for apps opened from now on.
    function setSmoothText(on) {
        ShellSettings.set("smoothText", on);
        Quickshell.execDetached(["sh", "-c", `mkdir -p "$HOME/.config/graphite" && printf ${on ? "smooth" : "standard"} > "$HOME/.config/graphite/text" && hyprctl reload`]);
    }

    // The Control Panel's Apps › Get apps and Apps › Installed apps (CpAppsList.qml).
    function openAppStore() {
        ShellState.openSettings("apps-get");
    }

    function openApps() {
        ShellState.openSettings("apps-installed");
    }

    // The system, the apps and Graphite itself, on the Control Panel's Updates page.
    function updateEverything() {
        ShellState.openSettings("updates");
        Updates.install();
    }

    // In the background: the password once (pkexec's window), then notifications as it goes.
    function setUpGaming() {
        Quickshell.execDetached(["sh", "-c", [
            "notify-send -a 'Graphite' -i applications-games 'Setting up gaming' 'Installing Steam, Minecraft and graphics drivers. This takes a few minutes.'",
            `if pkexec env GRAPHITE_USER="$USER" bash "${linux}/gaming.sh" --background > /tmp/graphite-gaming.log 2>&1; then`,
            "  notify-send -a 'Graphite' -i applications-games 'Gaming set up' 'Steam and the Modrinth App are installed. If new drivers were installed, restart.'",
            "else",
            "  notify-send -a 'Graphite' -i dialog-warning -h string:x-graphite-open:settings:apps 'Gaming setup didn'\\''t finish' 'Try again from Apps in the Control Panel. Details: /tmp/graphite-gaming.log'",
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
        command: ["sh", "-c", "for f in \"$HOME/.local/share/graphite/apps\"/*; do [ -f \"$f\" ] && echo \"$(sed -n 's/^kind=//p' \"$f\") $(basename \"$f\")\"; done; flatpak list --app --columns=application 2>/dev/null | sed 's/^/flatpak /'; pacman -Qq \"$@\" 2>/dev/null | sed 's/^/arch /'", "sh", "steam"].concat(Object.values(root.archFor), Object.values(root.vendorFor).map(app => app.id))
        stdout: StdioCollector {
            onStreamFinished: {
                const sources = {};
                const flatpaks = {};
                const arch = {};
                for (const line of this.text.split("\n")) {
                    const [kind, id] = line.trim().split(" ");
                    if (!kind || !id) continue;
                    if (kind === "arch") {
                        arch[id] = true;
                        continue;
                    }
                    sources[id] = kind;
                    if (kind === "flatpak") flatpaks[id] = true;
                }
                root.sources = sources;
                root.flatpaks = flatpaks;
                root.archInstalled = arch;
                // Installs that have finished leave the busy list.
                const busy = {};
                for (const id of Object.keys(root.installing)) {
                    const done = root.isInstalled(id) && (root.archFor[id] === undefined && root.vendorFor[id] === undefined || root.nativeInstalled(id));
                    // Ten minutes on, it didn't work (install-app.sh said why).
                    if (!done && Date.now() - root.installing[id] < 600000) busy[id] = root.installing[id];
                }
                root.installing = busy;
            }
        }
    }

    Timer {
        id: refreshSoon
        interval: 4000
        // Again until what is being installed is in (an app from Arch can take a minute or two).
        repeat: Object.keys(root.installing).length > 0
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
