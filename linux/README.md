# How Graphite works

This page is for the curious and for anyone working on Graphite. For what Graphite is and how to
install it, see the [main README](../README.md).

Graphite is three layers on top of Arch Linux:

- **[Hyprland](https://hypr.land)** (0.57, with its Lua config) is the compositor: it draws the
  windows, moves them and handles the keys. Its config is `hypr/hyprland.lua`.
- **The shell**, written in QML with [Quickshell](https://quickshell.org) (0.3), is everything
  Graphite draws itself: the taskbar, Start, the Control Panel, Task Manager, notifications, the
  sign-in and lock screens. It lives in `quickshell/` and runs as `qs -c graphite`.
- **System parts** in `system/` do what needs an administrator (updates, drives, the security
  sweep) without a terminal: a root-owned helper, an update service and polkit rules, put in
  place by `system/install.sh`.

## The parts

Paths are under `linux/`; `modules/` and `services/` are under `quickshell/`.

### The desktop

| Part | Where |
| --- | --- |
| The wallpaper: a soft glow from the top centre over a faint grid, drifting slowly while no window covers it (the live wallpaper). The sign-in and lock screens stand on it too | `modules/BackdropGlow.qml`, `modules/Backdrop.qml` |
| Home on an empty desktop: search and Recent, with a greeting the first time it shows after signing in | `modules/Home.qml` |
| The taskbar: a pill floating over the bottom edge, with pinned and running apps, folders, tagged windows, live previews and auto-hide. A pill's menu can minimise all of an app's windows | `modules/Bar.qml`, `TaskButton.qml`, `Popover.qml`, `Previews.qml`, `TagPanel.qml` |
| The bar's arrangement and window tags, shared with the Windows version | `services/Taskbar.qml`, `services/lib/` (from `taskbar-model.js`, `window-tags.js`) |
| Start (Super) and quick search (Alt+Space): apps (most used this month first), files, folders, settings and commands, with aliases, pins and labels | `modules/Launcher.qml`, `LauncherView.qml`, `services/Search.qml` |
| Menus for the bar, apps, windows, folders and the launcher | `modules/Menu.qml`, `services/Menus.qml` |
| Tray icons over the chevron. A right click opens the app's own menu, drawn by the shell | `modules/TrayPanel.qml`, `Menus.openTrayMenu` |
| Quick settings: Wi-Fi networks to join, Bluetooth devices to pair, where the sound goes, aeroplane mode, night light, volume and what's playing | `modules/QuickSettings.qml`, `NetworkList.qml`, `BluetoothList.qml`, `SoundDeviceList.qml` |
| Notifications: the shell is the notification server. Pop-ups show in the top-right corner and stay in the calendar panel until dismissed. A click brings the app forward (back from minimised, or started if it has no window); Graphite's own notifications open the page or file they're about | `services/Notifs.qml`, `modules/Toasts.qml`, `CalendarPanel.qml`, `NoteCard.qml` |
| Alt+Tab with live previews | `modules/Switcher.qml` |
| Task view (Super+Tab): every window as a live preview, and the desktops | `modules/TaskView.qml` |
| Task Manager (Ctrl+Shift+Esc): apps (with the processes they started), background processes and the desktop's own parts; end task; graphs of the processor, memory, disks, network and graphics card; the startup apps | `modules/TaskManager.qml`, `services/Tasks.qml`, `system/task-sample.sh` |
| Snipping Tool (Print, Super+Shift+S; Super+Shift+R records): an area, a window or the screen, after a delay if wanted. Screenshots are copied as an image and saved; recordings (wf-recorder or gpu-screen-recorder) are saved and copied as the file, ready to paste into a chat or a folder | `modules/CaptureTool.qml`, `services/Capture.qml`, `system/screenshot.sh` |
| Volume pop-up for the volume keys and the mouse wheel's side tilt | `modules/VolumePopup.qml` |
| Smooth wheel scrolling in every scrolling list (the Control Panel, Start, quick settings, notifications, Task Manager): a notch glides 160 px, and quick turns add up; touchpads keep Qt's own scrolling | `modules/WheelScroll.qml` |
| System sounds: signing in and out, a password asked for, notifications, devices plugged in or out, screenshots (KDE's Ocean set) | `services/Sounds.qml` |
| The shell comes back by itself a few seconds after it stops (a crash, or the computer running out of memory), as Windows' taskbar does | `system/shell.sh` (started by `hypr/hyprland.lua`) |

### Signing in

| Part | Where |
| --- | --- |
| Sign-in screen (greetd runs it on a small Hyprland of its own): a clock curtain, then a 4-digit PIN that signs in on the fourth digit, or the password. A sweep while it checks, a shake and the tries left when wrong, a 30-second wait and the hint after three, a Caps Lock warning, and a welcome | `quickshell/greeter.qml`, `modules/LoginView.qml`, `hypr/greeter.lua`, `greetd/setup.sh`, `system/pin-check` |
| Lock screen (Super+L, Lock, and before sleep): the same look, the password checked by PAM | `modules/LockScreen.qml` |
| Apps stay signed in: a keyring for their saved sign-ins, as Windows' Credential Manager, opened at sign-in without a password of its own (PIN or password). Chromium and Electron apps (Claude, VS Code, Chromium, Chrome) are told to use it, as they only do by themselves on desktops they know | `system/session.sh` (gnome-keyring) |

### The Control Panel

Modelled on Windows Settings, with "Find a setting" (Ctrl+F) at the top of its sidebar. It's
opened from Start's gear, quick settings, the bar's menu, or
`qs -c graphite ipc call settings page <id>`. Settings are kept as `settings.json` in the
shell's state folder, `~/.local/state/quickshell/by-shell/<id>/` (`services/ShellSettings.qml`
lists every one). Graphite's other records (where windows were, the storage and security
results) are in `~/.local/state/graphite/`.

| Page (id) | What's on it | Where |
| --- | --- | --- |
| Network & internet (`network`) | Wi-Fi, cable, VPN, proxy, aeroplane mode | `modules/CpNetwork.qml`, `services/Network.qml` |
| Bluetooth & devices (`devices`) | Pairing, mouse and touchpad, keyboard layout, printers | `modules/CpDevices.qml` |
| Display (`display`) | Resolution, refresh rate, scale, rotation, HDR, night light | `modules/CpDisplay.qml`, `services/Displays.qml` |
| Sound (`sound`) | Outputs and inputs in order of preference, devices turned off, system sounds | `modules/CpSound.qml`, `services/SoundDevices.qml` |
| Power & battery (`power`) | Power mode, when to lock, turn the screen off and sleep | `modules/CpPower.qml`, `services/Power.qml` |
| Personalisation (`personalise`) | Dark, light or auto; the accent; blur, animation speed, window animations and the live wallpaper; smoother text; Home; the taskbar; tiling, window zones, remembering windows; apps without the desktop's title bar | `modules/CpPersonalise.qml`, `services/Look.qml` |
| Apps (`apps`, `apps-installed`, `apps-get`) | Installed apps, Get apps, the default browser, startup apps, Set up gaming | `modules/CpApps.qml`, `CpAppsList.qml`, `services/Desktop.qml`, `services/Apps.qml` |
| Shortcuts (`shortcuts`) | Change any shortcut, or add ones that open apps | `modules/CpShortcuts.qml`, `services/Hotkeys.qml` |
| Accounts (`accounts`) | Your name, password, sign-in PIN and hint; other people | `modules/CpAccounts.qml` |
| Time & language (`time`) | Time zone, region, the computer's name | `modules/CpTime.qml` |
| Updates (`updates`) | [Updates](#updates) | `modules/CpUpdates.qml`, `services/Updates.qml` |
| Privacy & security (`security`) | The [security sweep](#the-security-sweep), the firewall, locking, disk encryption, app permissions | `modules/CpSecurity.qml`, `services/Security.qml` |
| Drives (`drives`) | [Drives](#drives) | `modules/CpDrives.qml`, `services/Drives.qml` |
| Storage (`storage`, `storage-clean`) | [Storage and clean-up](#storage-and-clean-up) | `modules/CpStorage.qml`, `CpCleanup.qml`, `services/Storage.qml` |
| System (`system`) | The processor, memory and graphics; reload the desktop | `modules/CpSystem.qml`, `services/Machine.qml` |
| Troubleshoot (`troubleshoot`) | Checks graphics, folders, Flathub apps and more, with fixes; the apps that didn't open, and why (each also says so in a notice) | `modules/CpTroubleshoot.qml`, `services/Diagnose.qml`, `system/diagnose.sh`, `system/launch.sh` |

## The look

The look is called Vesper: graphite surfaces, 1 px hairlines, tight Inter type and one accent.
`quickshell/config/Theme.qml` holds it, written by hand (the older `npm run build:qml-theme`
refuses to overwrite it). Personalisation chooses:

- **Accent:** indigo (the default), blue, mint, amber or rose.
- **Background blur:** the taskbar, pop-ups and Start see-through over a blur, or solid.
- **Animation speed:** 0.5× to 1.5×; every animation's length is divided by it.
- **Window animations:** off, and windows and the shell only fade, briefly.
- **Live wallpaper:** the glow drifts and breathes while no window covers it.

`services/Look.qml` follows the choices. Hyprland gets them through a `graphite_look = {...}`
line in its `desk.lua`, which `hyprland.lua` reads last. Apps follow too:

- GTK 4 (libadwaita) and GTK 3 apps such as Files get the same colours and accent
  (`gtk/`, from `npm run build:gtk-theme`; `gtk/apply.sh` writes them and the accent into
  `~/.config/gtk-{3,4}.0/gtk.css`). Files needs a restart to take new colours.
- The kitty terminal gets `kitty/vesper.conf` with the accent, and open terminals reload.
- Capitaine cursors, and Papirus icons in the shell.

**Text** is drawn the MacType way: slight hinting, subpixel smoothing and FreeType's stem
darkening for fuller strokes (`fonts/fonts.conf`, and `FREETYPE_PROPERTIES` in
`hyprland.lua`). Personalisation's **Smoother text** turns the stem darkening off and on.

## Windows

Windows float, as on Windows: they open centred, move by their title bar and resize from their
edges. **Tile windows** (Personalisation, or the bar's menu) switches to Hyprland's tiling and
back.

**Title bars** (minimise, maximise, close; drag to move, double-click to maximise) are drawn
for apps that leave theirs to the desktop, such as kitty, GTK 3 dialogs and Qt apps. They're 32
px tall, with rounded buttons. It's Hyprland's hyprbars plugin with Graphite's additions
(`hypr/titlebars/`), built for the Hyprland installed, and rebuilt when Hyprland's libraries
change. X11 apps' own title bars move their windows too (Steam), and apps' own minimise buttons
work (Discord, Steam). Personalisation lists the apps that go without one.

**Snapping:** Super+Left and Super+Right fill half the screen; Super+Up maximises.

**Window zones**, as PowerToys' FancyZones: hold **Shift** while dragging a window by its title
bar and the zones show; let go over one and the window fills it, its title bar inside the zone.
Near the line between two zones it fills both; with **Ctrl** held too, every zone from where
Ctrl went down to the one under the pointer. Personalisation › **Window zones** (or Start's "Edit
window zones") picks a layout or edits your own: click a zone to split it (Shift: across), drag
a line to move it, right-click to join two. `services/Zones.qml`, `modules/ZonesOverlay.qml`,
`modules/ZoneEditor.qml`. Hyprland reports no drags, so the left button reaches the shell from
Graphite's title-bar plugin (`hypr/titlebars/graphite-drags.cpp`, which also keeps the drag
going when Shift goes down), and Shift and Ctrl from `hyprland.lua`'s keyboard event.

**Windows remember where they were** (`services/WindowMemory.qml`). Each app's windows are
kept in `~/.local/state/graphite/windows.json`: the screen, the place on it, the size, and
whether the window was maximised or docked into zones. When the app opens a window again, after
a restart too, it moves back there, kept inside the screen if the screens have changed.

- An app with several windows has a place for each. A new window takes the place of one that
  opened with the same title; browsers swap back once their pages load.
- Left alone: games and Windows programs, windows that open full screen, splash screens,
  dialogs (`hyprland.lua` tags modal ones `graphite-dialog`), tabs, pinned windows, and
  everything while windows tile.
- A window opens centred and slides into place a moment later. Placing it before its first
  frame would need Hyprland's `window.open_early` hook, which crashes Hyprland 0.57 when it
  resizes.
- Personalisation › **Remember where windows were** turns it off.
- `qs -c graphite ipc call windows state` shows the record, `windows forget` clears it.

**Window tabs** are Hyprland's groups, styled in `hyprland.lua`: drag a window onto another,
drag a tab off to split, middle-click a tab to close it.

## Apps

**Apps** in the Control Panel lists everything installed, to open or uninstall (the desktop's
own parts are kept). **Get apps** installs more with one click, from popular picks or a search.

- Apps come from **Arch Linux's own packages** when Arch has them (they use the system's
  libraries and graphics driver, so they open faster and update with the system), and from
  **Flathub** otherwise. A Flathub app that Arch also has shows "Use Arch's version".
- **From their makers:** a few apps come from their makers, where Flathub's copy doesn't do the
  job (`vendorFor` in `services/Desktop.qml`). Unity Hub comes from Unity's own package
  repository, checked as apt checks it (its index signed with Unity's key, `apps/unity.asc`),
  into `~/Applications/Unity Hub`, with no password. On Flathub, Unity runs in a sandbox where a
  game that uses Steam can't reach Steam.
- **From GitHub:** paste a project's link (or `owner/repo`) into the search, or search words
  and GitHub's most starred matches show too. Check says what installing it would do, and from
  whom, before anything is installed: Arch's or Flathub's copy when the project is there, or
  its newest release for 64-bit Linux (an AppImage, a Flatpak, an Arch package, a `.deb`, or a
  `.tar.gz`/`.zip` unpacked into `~/Applications`, with a command in `~/.local/bin` for
  terminal programs). `apps/github.sh` does the finding and installing.
- Installing asks for an administrator's PIN or password, as Windows does.

**Opening a download installs it**, with a notification while it does
(`apps/install-app.sh`; `apps/register.sh` makes it the opener for these files):

| File | Goes |
| --- | --- |
| `.deb` (Ubuntu and Debian apps) | Into an Ubuntu 24.04 container made the first time ([Distrobox](https://distrobox.it): it shares your home, display, sound and GPU, so the app runs at full speed), its menu entries brought out to the desktop |
| `.AppImage` | `~/Applications`, made runnable, with a launcher entry |
| `.flatpakref`, `.flatpak` | Flatpak, for you |
| `.pkg.tar.zst` | pacman (asks for the password) |

**Apps open quickly from a hard drive:** what each app reads is noted, and the most used are
read into memory after signing in (`system/warm.sh`, `system/launch.sh`).

**When memory runs out,** Linux ends one process, and systemd used to close the whole app
around it. Apps are started with `OOMPolicy=continue` (`system/launch.sh`), and so are the
ones that move themselves into a place of their own (`system/user-manager.conf`). The
compressed swap (zram) is as large as the memory (`system/zram-generator.conf`,
`system/99-graphite-memory.conf`).

## Games

Control Panel › Apps › **Set up gaming** (or Start's "Set up gaming", or the installer) runs
`gaming.sh` after one password: the drivers for the machine's graphics card with their 32-bit
parts, Steam with Proton, the Modrinth App for Minecraft, GameMode, MangoHud, gamescope and
power profiles. Lutris and Heroic (in Get apps) cover Battle.net, EA, Ubisoft, Epic and GOG.
League of Legends and Valorant can't run on Linux: Riot's Vanguard anti-cheat refuses it.

- **Low lag:** games may draw without waiting for the screen (tearing, for the least delay),
  and the shell stops its background checks while a game is full screen. Variable refresh
  rate stays off: on an HDR screen with NVIDIA it flashed whenever a window went full screen.
- **Full-screen games stay usable** (`services/Taskbar.qml`). A window picked while a game has
  the screen (from the taskbar, Task view or Alt+Tab) comes up over it and keeps the keyboard:
  games can no longer take it back by themselves, though their own pop-ups still can. Clicking
  the game again brings it back in front.
- **Steam games on exFAT and FAT drives:** Proton builds each game's Windows folder (its
  "prefix") with symlinks, which exFAT can't hold, so those games wouldn't start. On such a
  library, `~/.local/share/proton-prefixes` is mounted over `steamapps/compatdata`
  (`system/steam-prefixes.sh`, `graphite-admin steam-prefixes`), after a drive is connected and
  when Steam's library list changes. It's released before a drive is disconnected or formatted.
- **NVIDIA:** 10 GB for compiled shaders instead of the driver's 1 GB, so big modded games
  don't compile them all again each start.
- For big Minecraft modpacks, give Minecraft 6 to 8 GB in the Modrinth App's settings.

## Updates

Updates need no terminal (`services/Updates.qml`). Every few hours the desktop checks what's
waiting and says so once:

- Arch's packages (`checkupdates`, which never touches the real package list);
- apps from the AUR, installed with yay, say (`system/aur-update`);
- Flatpak apps from Flathub;
- Graphite's own commits.

Control Panel › **Updates** installs everything with one button, and shows Arch's news since
the last update first, as some updates need a step by hand. The system half runs as root in
`graphite-update.service` (an administrator may start it without a password); the person's half
(their apps, the Ubuntu container, a `git pull` of Graphite) runs alongside, apart from the
shell, as a pull reloads the shell. A new kernel asks for a restart. When Graphite's system
parts have changed, the page offers **Finish updating Graphite**, which puts them in place after
the administrator's password. **Install updates automatically** runs it once a day.

AUR apps are built in a throwaway systemd sandbox (`DynamicUser`, which sees nobody's home),
never as the person: as the update needs no password, anything they could change could
otherwise be installed by root. Root then installs only the packages it built, in place of ones
that came from no repository, so a build can't replace one of Arch's own. What a build needs
from Arch is installed for the build and removed after it. A package that needs another from
the AUR, or doesn't build, is left as it was, with a note on the page.

## The security sweep

Privacy & security runs a sweep every day or week, and when asked (`system/security-sweep.py`,
`services/Security.qml`). It checks:

- known security holes in installed packages (arch-audit);
- the firewall, what's open to the network and remote sign-in;
- wrong passwords, and what starts by itself;
- Flathub apps that can see all your files;
- how old the updates are, and Secure Boot;
- malware in downloads and apps (ClamAV), if turned on.

A notification says when something needs a look, and the page offers the fixes, with their
progress on the button.

## Storage and clean-up

The Storage page (`system/storage.py`, `services/Storage.qml`) shows each drive and the folders
that fill it most, Steam libraries down to their games. Its clean-up wizard
(`modules/CpCleanup.qml`) offers, each saying what deleting it costs:

- caches and leftovers: apps' and Claude's caches, old Claude Code versions, compiled shaders,
  Unreal's caches, Fab downloads, Rust and Unity build folders, old updates and logs;
- the screenshots and recordings since the last clean-up, to pick the ones for the Bin;
- old or big downloads;
- Claude Code chats over an age;
- the Bin.

It looks again once a week, with a reminder when a clean-up would free a gigabyte.

## Drives

The Drives page lists every drive, to connect, eject, format or erase (never the system's own).

- A drive connected (on the Drives page or in Files) is connected again at sign-in and when
  plugged in, until it's disconnected on the Drives page (`drivesConnected` in settings).
- ext4 drives are formatted with no space held back for the system (`-m 0`), as the system's
  own drive is never formatted here.
- A Windows dynamic disk opens (ldmtool), or becomes a basic disk with its files kept
  (`graphite-admin dynamic-disks`, `dynamic-to-basic`).
- **Moving the system to a faster drive** (a hard drive to an SSD), as it is:
  `sudo system/move-system.sh /dev/sdX` lays the new drive out as the installer does and copies
  the system over; `... again` copies the last changes and restarts into it. The old drive
  stays startable from the boot menu.

**Files** (Nautilus) gets a Size column that gives folders their size too, a Drives place with
the space left on each drive (as This PC), Delete Permanently, and opens folders for the rest
of the desktop (`files/folder-sizes.py` with nautilus-python, `files/drives.sh`).

## Keys

| Keys | |
| --- | --- |
| Super (on its own) | Start: apps, files, settings; its gear opens the Control Panel |
| Alt+Space | Quick search |
| Alt+Tab / Alt+Shift+Tab | Switch windows (let go of Alt to switch) |
| Super+Tab | Task view |
| Ctrl+Shift+Esc | Task Manager |
| Super+Left / Right | Snap to the left or right half (tiling: move focus) |
| Super+Up / Down | Maximise; restore or minimise |
| Super+Shift+arrows | Move a window that way |
| Super+Enter, Super+E | Terminal, Files |
| Super+L | Lock |
| Super+Q | Close the window |
| Super+F, Super+Shift+F | Maximise; full screen |
| Super+V | Float or tile one window |
| Super+G | Make or break up a tab group; Super+` moves through its tabs |
| Super+Ctrl+O | Pull a window out of its group |
| Print, Super+Shift+S | Snipping Tool: a screenshot of an area, a window or the screen |
| Super+Shift+R | Record the screen (again to stop) |
| Side scroll (tilt the wheel), volume keys | Volume up or down (right is up), mute |
| Super+1..9, Super+Shift+1..9 | Go to, or move a window to, a desktop |
| Super+drag, Super+right-drag | Move, resize |

Control Panel › Shortcuts changes any of these and adds ones that open apps. On the bar: drag a
pill to move it, and hold it over another for half a second to make a folder. Right-click a
pill for its menu (pin, run as administrator, tag a window, minimise all, close), or the bar
itself for its options.

## Run it on your own Arch install

On an Arch install of your own (a VM or a real machine), `setup.sh` installs what the shell
needs, puts the system parts in place, and links the configs to the checkout, so the shell runs
straight from it:

```bash
git clone https://github.com/CookieJarTools/Graphite.git
bash Graphite/linux/setup.sh
```

Then start the desktop from the console with `start-hyprland`. `greetd/setup.sh` adds
Graphite's sign-in screen. The installer puts the checkout in `/opt/graphite-desk`, owned by
the person who installed it, and Updates pulls it from there.

To try it in VirtualBox from Windows, `vm/make-vm.ps1` builds a VM that installs Arch Linux and
Graphite by itself; see [vm/README.md](vm/README.md). The USB installer is described in
[installer/README.md](installer/README.md).

## Working on it

Quickshell reloads on the file changes it sees. To reload by hand, use Start's **Reload the
desktop**, or:

```bash
qs -c graphite ipc call settings reload
```

It may answer "Not ready to accept queries yet" just after starting; try again a moment later.
Hyprland reloads `hyprland.lua` on save, or with `hyprctl reload`. Check a config change first
with `Hyprland --verify-config -c <file>`, which starts no compositor.

The shell's log is `qs -c graphite log`. Its commands, for scripts and testing:

```bash
qs -c graphite ipc call launcher open
qs -c graphite ipc call palette toggle
qs -c graphite ipc call switcher next
qs -c graphite ipc call panel toggle quick        # quick, calendar or tray
qs -c graphite ipc call settings page storage     # any page id from the Control Panel table
qs -c graphite ipc call settings zones            # the window zones editor
qs -c graphite ipc call taskmanager open
qs -c graphite ipc call capture screenshot        # or record, cancel, stop
qs -c graphite ipc call taskbar items             # what the bar shows, as JSON
qs -c graphite ipc call windows state             # where windows will reopen
qs -c graphite ipc call menu tray 0               # a tray icon's menu, as a right click
notify-send "Build finished" "3 warnings"
```

Don't register hooks on a running Hyprland with `hyprctl eval` to test something: a hook that
resized a window in `window.open_early` crashed the whole desktop.
