# Graphite Desk for Linux

The Graphite Desk shell on Linux: [Hyprland](https://hypr.land) (0.55 or later, Lua config)
underneath, the shell itself written in QML with [Quickshell](https://quickshell.org) (0.3).
It draws from the same design system as the Windows version: `config/Theme.qml` is generated
from `design/graphite-desk/tokens.json` (`npm run build:qml-theme`).

| Part | Where |
| --- | --- |
| Desktop backdrop (no wallpaper; the shell draws the desktop) | `quickshell/modules/Backdrop.qml` |
| Floating taskbar: pinned and running apps, tray chevron, status, clock | `modules/Bar.qml`, `AppButton.qml`, `StatusButton.qml`, `Clock.qml` |
| Quick settings: Wi-Fi, Bluetooth, volume, media | `modules/QuickSettings.qml` |
| Calendar with the notifications still kept | `modules/CalendarPanel.qml`, `NoteCard.qml` |
| Tray icons (StatusNotifierItem) over the chevron | `modules/TrayPanel.qml` |
| Launcher (Super): apps and commands | `modules/Launcher.qml` |
| Alt+Tab with live previews | `modules/Switcher.qml` |
| Notification server and pop-ups | `services/Notifs.qml`, `modules/Toasts.qml` |
| Window tabs | Hyprland's groups, styled in `hypr/hyprland.lua` |
| Keys, look, start-up | `hypr/hyprland.lua` |

## Keys

| Keys | |
| --- | --- |
| Super | Launcher |
| Alt+Tab / Alt+Shift+Tab | Switch windows (let go of Alt to switch) |
| Super+Enter, Super+E | Terminal, files |
| Super+Q, Super+F, Super+V | Close, maximise, float |
| Super+G | Make or break up a tab group; Super+Tab moves through its tabs |
| Super+Ctrl+O | Pull a window out of its group |
| Super+1..9, Super+Shift+1..9 | Go to, or move a window to, a workspace |
| Super+drag, Super+right-drag | Move, resize |

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
notify-send "Build finished" "3 warnings"
```
