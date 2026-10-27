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

## Test it in a VMware VM

Windows 11 Home has no Hyper-V, so the VM is VMware Workstation Pro (free for personal use).

1. **Install VMware Workstation Pro** from Broadcom's site (a free account is needed).
2. **Get Arch Linux**: the ISO from <https://archlinux.org/download/>.
3. **Create the VM**: *Typical*, the ISO, guest OS *Linux / Other Linux 6.x kernel 64-bit*,
   4 cores, 8 GB of memory, a 40 GB disk. Then in its settings:
   - *Display*: tick **Accelerate 3D graphics** (Hyprland needs the GPU), 2 GB graphics memory.
   - *Options > Advanced*: firmware **UEFI**.
   - *Options > Shared Folders*: **Always enabled**, add `F:\Dev\StartMenu` as `StartMenu`.
4. **Install Arch**: boot the ISO and run `archinstall`. Choose: profile *Minimal*, audio
   *pipewire*, network *NetworkManager*, a user with sudo. Reboot into the new system.
5. **Mount the shared folder** (this once; setup makes it permanent):
   ```bash
   sudo pacman -S --needed open-vm-tools
   sudo mkdir -p /mnt/hgfs && sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other
   ```
6. **Run the setup**: `bash /mnt/hgfs/StartMenu/linux/setup.sh`
7. **Start it**: log in on the console and run `start-hyprland`.

VMware keeps some keys (Ctrl+Alt) for itself; click into the VM window first so the guest
gets Super and Alt+Tab.

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
