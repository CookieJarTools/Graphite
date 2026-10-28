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
| Login screen (greetd runs it on a small Hyprland), with a welcome animation on the right password | `quickshell/greeter.qml`, `modules/LoginView.qml`, `hypr/greeter.lua`, `greetd/setup.sh` |
| Lock screen (Super+L, Lock, before sleep): the same look, the password checked by PAM | `modules/LockScreen.qml` |
| Settings window | `modules/SettingsWindow.qml`, kept in `settings.json` (`services/ShellSettings.qml`) |
| Quick settings: Wi-Fi, Bluetooth, volume, media | `modules/QuickSettings.qml` |
| Calendar with the notifications still kept | `modules/CalendarPanel.qml`, `NoteCard.qml` |
| Tray icons (StatusNotifierItem) over the chevron | `modules/TrayPanel.qml` |
| Launcher (Super) and Alt+Space search: apps, files, folders, commands, aliases, pins, labels | `modules/Launcher.qml`, `LauncherView.qml`, `services/Search.qml` |
| Apps in the Graphite colours (GTK 4 and 3), Capitaine cursors | `gtk/` (from `npm run build:gtk-theme`), `gtk/apply.sh` |
| Alt+Tab with live previews | `modules/Switcher.qml` |
| Notification server and pop-ups | `services/Notifs.qml`, `modules/Toasts.qml` |
| Window tabs: drag a window onto another, drag a tab off to split, middle-click closes | Hyprland's groups, styled in `hypr/hyprland.lua` |
| Keys, look, start-up, floating or tiling windows | `hypr/hyprland.lua` |

Windows float, as on Windows: they open centred, move by their title bar and resize from
their edges. **Tile windows** (Settings, or the bar's right-click menu) switches to
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
or uninstall (the desktop's own parts are kept), and gets more from Flathub with one click:
popular picks, or a search.

Opening a download installs it in the right place, with a notification while it does, and
the app then sits in the launcher (right-click it there to uninstall):

| File | Goes |
| --- | --- |
| `.deb` (Ubuntu and Debian apps, such as Claude Desktop) | Into an Ubuntu 24.04 container made the first time ([Distrobox](https://distrobox.it): it shares your home, display, sound and GPU, so the app runs at full speed), its menu entries brought out to the desktop |
| `.AppImage` | `~/Applications`, made runnable, with a launcher entry |
| `.flatpakref`, `.flatpak` | Flatpak, for you |
| `.pkg.tar.zst` | pacman (asks for the password) |

The **App store** (launcher, or Settings) is GNOME Software on Flathub: one click to install.
`apps/install-app.sh` does the installing and `apps/register.sh` makes it the opener for those
files; the shell runs the latter at start.

## Games

Settings → **Set up gaming** (or the launcher's "Set up gaming") runs `gaming.sh` in a
terminal: the drivers for the machine's GPU with their 32-bit parts, Steam (with Proton),
Prism Launcher for Minecraft with Java 8, 17 and 21, GameMode, MangoHud, gamescope and power
profiles. Minecraft gets settings against the stutter modpacks show: half the memory (4 to
12 GB), fixed from the start, garbage collection tuned for short pauses (Aikar's flags),
GameMode on and the discrete GPU. Hyprland lets games draw without waiting for the screen
(tearing allowed, for the least lag), uses variable refresh in fullscreen, and the shell stops
its background checks while a game is fullscreen. On a real machine only: the VM has no GPU.

## Text

Text is drawn the MacType way: slight hinting, subpixel smoothing and FreeType's stem
darkening for fuller strokes (`fonts/fonts.conf`, and `FREETYPE_PROPERTIES` in
`hyprland.lua`). Settings → **Smoother text** turns the stem darkening off and on.

## Keys

| Keys | |
| --- | --- |
| Super | Launcher |
| Alt+Space | Compact search |
| Alt+Tab / Alt+Shift+Tab | Switch windows (let go of Alt to switch) |
| Super+Left / Right | Snap to the left or right half (tiling: move focus) |
| Super+Up / Down | Maximise; restore or minimise |
| Super+Enter, Super+E | Terminal, files |
| Super+L | Lock |
| Super+Q, Super+F, Super+V | Close, maximise, float or tile one window |
| Super+G | Make or break up a tab group; Super+Tab moves through its tabs |
| Super+Ctrl+O | Pull a window out of its group |
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
