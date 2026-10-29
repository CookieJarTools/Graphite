# Graphite Desk for Linux

The Graphite Desk shell on Linux: [Hyprland](https://hypr.land) (0.55 or later, Lua config)
underneath, the shell itself written in QML with [Quickshell](https://quickshell.org) (0.3).
It draws from the same design system as the Windows version: `config/Theme.qml` is generated
from `design/graphite-desk/tokens.json` (`npm run build:qml-theme`).

| Part | Where |
| --- | --- |
| Desktop backdrop (no wallpaper; the shell draws the desktop) | `quickshell/modules/Backdrop.qml` |
| Home on an empty workspace: search and Recent, the sign-in greeting | `modules/Home.qml` |
| Floating taskbar: pinned and running apps, folders, tagged windows, previews, auto-hide | `modules/Bar.qml`, `TaskButton.qml`, `Popover.qml`, `Previews.qml`, `TagPanel.qml` |
| The bar's arrangement and window tags (the Windows version's own code) | `services/Taskbar.qml`, `services/lib/` (from `taskbar-model.js`, `window-tags.js`) |
| Menus (bar, apps, windows, folders, launcher) | `modules/Menu.qml`, `services/Menus.qml` |
| Login screen (greetd runs it on a small Hyprland): a clock curtain, then a 4-digit PIN (signs in on the fourth digit; `system/pin-check`, set in Accounts) or the password, with a sweep while it checks, a shake and the tries left when wrong, a 30-second lock-out and the hint after three, a Caps Lock warning, and a welcome | `quickshell/greeter.qml`, `modules/LoginView.qml`, `hypr/greeter.lua`, `greetd/setup.sh` |
| Lock screen (Super+L, Lock, before sleep): the same look, the password checked by PAM | `modules/LockScreen.qml` |
| Control Panel: network, Bluetooth and devices, display (resolution, scale, HDR, night light), sound, power, personalisation, apps, accounts, time, updates, privacy and security, system | `modules/ControlPanel.qml`, `Cp*.qml`; `services/Displays.qml`, `Power.qml`, `Machine.qml`, `Updates.qml`; kept in `settings.json` (`services/ShellSettings.qml`) |
| Task Manager (Ctrl+Shift+Esc): apps and background processes, end task, performance graphs | `modules/TaskManager.qml`, `services/Tasks.qml`, `system/task-sample.sh` |
| Task view (Super+Tab): every window as a live preview, and the desktops | `modules/TaskView.qml` |
| Shortcuts page: change any shortcut, add ones that open apps | `modules/CpShortcuts.qml`, `services/Hotkeys.qml` |
| Snipping Tool (Print, Super+Shift+S; Super+Shift+R records): a rectangle, a window or the screen, after a delay if wanted; screenshots copied and saved, recordings with wf-recorder | `modules/CaptureTool.qml`, `services/Capture.qml`, `system/screenshot.sh` |
| Drives page: every drive, connect, eject, format or erase (never the system's); a Windows dynamic disk opened (ldmtool) or made a basic disk with its files kept | `modules/CpDrives.qml`, `services/Drives.qml`, `system/graphite-admin` (`dynamic-disks`, `dynamic-to-basic`) |
| Troubleshoot page, and a notice with the reason when an app doesn't open | `modules/CpTroubleshoot.qml`, `services/Diagnose.qml`, `system/diagnose.sh`, `system/launch.sh` |
| Administrator changes and updates without a terminal: a root-owned helper, an update service, polkit rules | `system/` (`install.sh` puts them in place) |
| Installer on the USB stick: friendly screens over `installer/graphite-install.sh` | `quickshell/installer.qml`, `installer/gui.lua`, `installer/build-iso.sh` |
| Quick settings: Wi-Fi networks to join, Bluetooth devices to pair, where the sound goes, aeroplane mode, night light, volume, media | `modules/QuickSettings.qml`, `NetworkList.qml`, `BluetoothList.qml`, `SoundDeviceList.qml` |
| Calendar with the notifications still kept | `modules/CalendarPanel.qml`, `NoteCard.qml` |
| Tray icons (StatusNotifierItem) over the chevron | `modules/TrayPanel.qml` |
| Launcher (Super) and Alt+Space search: apps, files, folders, commands, aliases, pins, labels | `modules/Launcher.qml`, `LauncherView.qml`, `services/Search.qml` |
| Apps in the Graphite colours (GTK 4 and 3), Capitaine cursors | `gtk/` (from `npm run build:gtk-theme`), `gtk/apply.sh` |
| Alt+Tab with live previews | `modules/Switcher.qml` |
| Notification server and pop-ups | `services/Notifs.qml`, `modules/Toasts.qml` |
| Window tabs: drag a window onto another, drag a tab off to split, middle-click closes | Hyprland's groups, styled in `hypr/hyprland.lua` |
| Keys, look, start-up, floating or tiling windows, animations as quick as Windows' | `hypr/hyprland.lua` |
| Title bars (minimise, maximise, close; drag to move, double-click to maximise) for apps that leave theirs to the desktop, such as Kitty, GTK 3 dialogs and Qt apps; X11 apps' own title bars drag their windows (Steam); a drag carries on when Shift goes down (window zones) | `hypr/titlebars/` (Hyprland's hyprbars plugin with Graphite's additions, built for the Hyprland installed) |
| System sounds: signing in and out, a password asked for, notifications, devices plugged in or out, screenshots (KDE's Ocean set); sound devices turned off | `services/Sounds.qml`, `services/SoundDevices.qml`, `modules/CpSound.qml` |
| Security sweep (Privacy & security), every day or week and when asked: known security holes in installed packages (arch-audit), the firewall, what's open to the network, remote sign-in, wrong passwords, what starts by itself, Flathub apps that see all files, how old the updates are, Secure Boot, and malware in downloads and apps (ClamAV, if turned on); a notification when something needs a look, with the fixes on the page | `system/security-sweep.py`, `services/Security.qml`, `modules/CpSecurity.qml` |
| Apps open quickly from a hard drive: what each app reads is noted, and the most used are read into memory after signing in | `system/warm.sh`, `system/launch.sh`, `services/Apps.qml` |
| Files: a Size column that gives folders their size too, a Drives place with the space left on each drive (as This PC), Delete Permanently, folders opening in Files | `files/folder-sizes.py` (with nautilus-python), `files/drives.sh`, `apps/register.sh` |

Windows float, as on Windows: they open centred, move by their title bar and resize from
their edges. **Tile windows** (Control Panel, Personalisation; or the bar's right-click menu) switches to
Hyprland's tiling and back; the choice is kept in `~/.config/graphite/windows`.

## Window zones

As PowerToys' FancyZones: hold **Shift** while dragging a window and the zones show; let go
over one and the window fills it. Near the line between zones it fills both; with **Ctrl**
held too, every zone from where Ctrl went down to the one under the pointer. Settings →
**Window zones** (or the launcher's "Edit window zones") picks a layout or edits your own:
click a zone to split it (Shift: across), drag a line to move it, right-click to join two.
`services/Zones.qml`, `modules/ZonesOverlay.qml`, `modules/ZoneEditor.qml`; `hyprland.lua`
passes the shell the left button (a bind that leaves the click to the app) and Shift and
Ctrl (its keyboard event: a bind going off mid-drag would end the drag).

## Installing apps

**Apps** (launcher, Settings, or the app store command) lists everything installed, to open
or uninstall (the desktop's own parts are kept), and gets more with one click: popular
picks, or a search. Apps come from Arch Linux's own packages when Arch has them (they use the
system's libraries and graphics driver, so they open faster and update with the system) and
from Flathub otherwise. A Flathub app that Arch also has shows "Use Arch's version". Installing
asks for an administrator's PIN or password, as Windows does.

Opening a download installs it in the right place, with a notification while it does, and
the app then sits in the launcher (right-click it there to uninstall):

| File | Goes |
| --- | --- |
| `.deb` (Ubuntu and Debian apps, such as Claude Desktop) | Into an Ubuntu 24.04 container made the first time ([Distrobox](https://distrobox.it): it shares your home, display, sound and GPU, so the app runs at full speed), its menu entries brought out to the desktop |
| `.AppImage` | `~/Applications`, made runnable, with a launcher entry |
| `.flatpakref`, `.flatpak` | Flatpak, for you |
| `.pkg.tar.zst` | pacman (asks for the password) |

**From GitHub:** paste a project's link (or `owner/repo`) into Get apps' search, or search
words and Get apps lists GitHub's most starred matches too. Check shows what installing it
would do, and from whom, before anything is installed: Arch Linux's or Flathub's copy when the
project is there (they update with the system), else its newest release's download for 64-bit
Linux (an AppImage, a Flatpak, an Arch package, a `.deb`, or a `.tar.gz`/`.zip` of a Linux
build, unpacked into `~/Applications` with a launcher entry, and a command in `~/.local/bin`
for terminal programs). A project that publishes only its code says so. `apps/github.sh` does
the finding and installing, with GitHub's own tool's sign-in (`gh`) when there is one.

The **App store** (launcher, or Settings) is GNOME Software on Flathub: one click to install.
`apps/install-app.sh` does the installing and `apps/register.sh` makes it the opener for those
files; the shell runs the latter at start.

## Games

Control Panel → Apps → **Set up gaming** (or the launcher's "Set up gaming", or the installer)
runs `gaming.sh` in the background after one password: the drivers for the machine's GPU
with their 32-bit parts, Steam (with Proton), the Modrinth App for Minecraft (it brings its
own Java), GameMode, MangoHud, gamescope and power profiles. For big modpacks, give Minecraft
6 to 8 GB in the Modrinth App's settings (it keeps them in its own database, so they can't be
preset). League of Legends and Valorant can't run on Linux: Riot's Vanguard anti-cheat
refuses it. Lutris and Heroic (in Get apps) cover Battle.net, EA, Ubisoft, Epic and GOG.

Hyprland lets games draw without waiting for the screen
(tearing allowed, for the least lag), uses variable refresh in fullscreen, and the shell stops
its background checks while a game is fullscreen. On a real machine only: the VM has no GPU.

## Updates

Updates need no terminal. Every few hours the desktop checks what's waiting (Arch's packages
with `checkupdates`, Flatpak apps, Graphite Desk's own commits) and says so once. Control
Panel → **Updates** installs everything with one button: the system half runs as root in
`graphite-update.service` (an administrator may start it without a password), the person's
half (their apps, the Ubuntu space, a `git pull` of Graphite Desk) alongside it, with its
progress on the page. Arch's news since the last update is listed first, a new kernel asks
for a restart, and **Install updates automatically** runs it once a day.

## Text

Text is drawn the MacType way: slight hinting, subpixel smoothing and FreeType's stem
darkening for fuller strokes (`fonts/fonts.conf`, and `FREETYPE_PROPERTIES` in
`hyprland.lua`). Control Panel → Personalisation → **Smoother text** turns the stem darkening off and on.

## Keys

| Keys | |
| --- | --- |
| Super (on its own) | Search: apps, files, settings; its gear opens the Control Panel |
| Ctrl+Shift+Esc | Task Manager |
| Alt+Space | Compact search |
| Alt+Tab / Alt+Shift+Tab | Switch windows (let go of Alt to switch) |
| Super+Left / Right | Snap to the left or right half (tiling: move focus) |
| Super+Up / Down | Maximise; restore or minimise |
| Super+Enter, Super+E | Terminal, files |
| Super+L | Lock |
| Super+Q, Super+F, Super+V | Close, maximise, float or tile one window |
| Super+G | Make or break up a tab group; Super+` moves through its tabs |
| Super+Ctrl+O | Pull a window out of its group |
| Super+Tab | Task view |
| Print, Super+Shift+S | Snipping Tool: a screenshot of an area, a window or the screen |
| Super+Shift+R | Record the screen (again to stop) |
| Side scroll (tilt the wheel), volume keys | Volume up or down (right is up), mute; a moment's pop-up over the bar |
| Super+1..9, Super+Shift+1..9 | Go to, or move a window to, a workspace |
| Super+drag, Super+right-drag | Move, resize |

On the bar: drag a pill to move it; hold it over another for half a second to make a folder.
Right-click a pill for its menu (pin, run as administrator, tag a window, minimise, close),
or the bar itself for its options.

## Test it in a VM

`vm/make-vm.ps1` builds a VirtualBox VM that installs Arch Linux and this shell by itself and
starts straight into it; see [vm/README.md](vm/README.md). The checkout is shared into the
VM, so the shell runs from it.

On an Arch install of your own (a VM or a real machine), `setup.sh` installs what the shell
needs and links the configs to the checkout; then start the desktop with `start-hyprland`.
In a VM, click into its window first so the guest gets Super and Alt+Tab.

## Working on it

The configs are links into the shared folder, so an edit on Windows is in the VM at once.
Quickshell reloads on file changes it sees; changes made from Windows may not reach it as
file events, so reload by hand: the launcher's **Reload the shell** command, or
`qs -c graphite kill && qs -c graphite -d`. Hyprland reloads `hyprland.lua` on save, or with
`hyprctl reload`.

The shell's log: `qs -c graphite log`. Its commands, for scripts and testing:

```bash
qs -c graphite ipc call launcher toggle
qs -c graphite ipc call switcher next
qs -c graphite ipc call panel toggle calendar   # quick, calendar or tray
qs -c graphite ipc call palette toggle
qs -c graphite ipc call settings open
qs -c graphite ipc call settings tiling true
qs -c graphite ipc call taskbar items           # what the bar shows, as JSON
notify-send "Build finished" "3 warnings"
```
