# Graphite for Windows

Graphite began as a shell for Windows 11, before it became a desktop for Linux. It's still
here, in the repository's root folder: a minimal Windows 11 shell built to the Graphite design
system, with no desktop icons, search first, and calm cards. Electron draws every surface; a
small C# helper does what Chromium can't (keyboard hooks, window management, the shell hook,
DWM previews).

The Linux desktop has grown well past it since. For that, see the [main README](../README.md)
and [How Graphite works](../linux/README.md). The Windows version hasn't changed since late
October 2026, so treat this page as a record of what it does.

## What it does

- **Launcher.** The bare Win key (and the taskbar Start button, and `Ctrl+Esc`) opens
  the launcher instead of the Windows Start menu: places, pinned apps, recent items,
  and grouped search over apps, recent files, folders and commands, with identifiers
  (type `CL` + Enter), labels, key chips and power actions (destructive ones need a
  second press). All other Win-key combos pass through.
- **Command palette.** `Alt+Space` opens the same search, compact and results-only,
  over a dimming scrim. Releasing Alt never opens the app's window menu.
- **Home replaces the desktop.** Whenever no app window is visible (all closed, all
  minimised, or `Win+D`), a full-screen backdrop with one search field and your recent
  items appears; typing turns it into the full launcher in place.
- **Sign-in intro.** The startup entry passes `--login`, which plays a short greeting
  ("Good afternoon, Sam") before handing over to Home. Skipped when Windows animation
  effects are off.
- **Alt+Tab replacement.** A switcher with live previews of every window (minimised
  ones show their icon), most recent first. Hold Alt: Tab or arrows move, W closes the
  selected window, Esc cancels; release Alt to switch.
- **Window tabs.** Drag a window by its title bar onto another window's title bar (or
  onto a group's tab strip): a slot tab shows where it will land, and on release the
  window shrinks into it. Only the active tab's window is shown, at the group's place
  and size. Click a tab to switch, its x to close it, pull it down to split it out, or
  drag the empty strip to move the group.
- **Taskbar.** A floating, centred bar replaces the Windows one:
  - one pill per app, its windows combined (a count shows how many; click to pick one),
    or one per window if you turn combining off;
  - hover a running pill for live previews of its windows;
  - pin apps (right-click, or from the launcher) so they stay when closed;
  - drag pills to reorder; drag one and hold it over another to make a folder, then
    name it; drop more apps on it to add them;
  - pin a category (right-click the bar, Pin category) for a folder of every app with
    that launcher label;
  - icons only or with names (right-click the bar, Show app names);
  - status glyphs open Quick Settings (`Win+A`), the clock opens notifications
    (`Win+N`), and the chevron shows the Windows taskbar for its tray icons.

  It hides while a maximised window has focus; push the pointer to the bottom edge to
  bring it back. The arrangement lives in `taskbar-model.js`.
- **Files.** `Win+E`, and any folder opened from the launcher or Home, opens Files: a
  translucent sidebar, tabs, one field that is both path and search, three densities,
  sortable columns, rename, new folder, copy/cut/paste, Recycle Bin, drag files out.
- **Toasts.** The shell's own notifications (for example when it recovers after a
  crash) as cards in the top-right corner.
- Lives in the **system tray**, where every piece can be switched on or off.

### Safety

Everything that changes Windows is undone when the app stops:

- The helper shows all hidden tab windows and restores the Windows taskbar (including
  its auto-hide setting) whenever it exits, for any reason it can see.
- Electron saves what is hidden, so even after a crash the next start puts it back,
  checking each window still belongs to the same program first.
- `Ctrl+Alt+Shift+Q` quits everything immediately (and so undoes everything).
- If all else fails: `Ctrl+Shift+Esc` opens Task Manager; restarting "Windows Explorer"
  there brings the Windows taskbar back.

## Run

```bash
npm install
npm start
```

`npm start` builds the helper (needs the .NET 10 SDK), the tray icon and the design
tokens before launching Electron. `npm run dist` builds the installer.

### Dev mode

```bash
npm run dev
```

Runs the launcher as an ordinary resizable window, without taking over your system:

- **Takeovers off.** Every hook and replacement starts off and is switched on per run,
  from the tray or with a flag (none of it is saved):

  | flag | turns on |
  | --- | --- |
  | `--palette` | `Alt+Space` command palette |
  | `--alttab` | Alt+Tab replacement |
  | `--tabs` | window tabs |
  | `--home` | Home on an empty screen |
  | `--taskbar` | the Graphite taskbar (hides the Windows one until dev mode exits) |
  | `--files` | `Win+E` opens Files |

  For example `npm run dev -- --tabs --alttab`. The Win-key launcher is switched on
  from the tray ("Replace Windows Start menu").
- **Nothing else changes.** Power buttons and the dark mode command only log, no
  startup entry is written, and settings live in `%AppData%/graphite-dev`, so the
  installed app is untouched and both can run side by side.
- **Previews.** The tray has Preview launcher, Preview palette, Preview Home, Play intro,
  Preview switcher and Test toast. To start on one: `npm run dev -- --preview=home`
  (or `palette`, `intro`, `switcher`).
- **Live reload.** Saving anything in `renderer/` reloads every page; saving `main.js`,
  `files-main.js` or `preload.js` restarts the app. Helper (C#) changes need a restart of `npm run dev`.
- **Poking the helper.** From any page's DevTools console, `api.devHelper('listwindows')`
  or `api.devHelper('tabmerge <hwnd> <hwnd>')` sends a raw helper command.
- **Panic shortcut.** `Ctrl+Alt+Shift+Q` quits the app and its helper.

### Tests

```bash
npm run test:e2e
```

Runs the helper and the app for real (about two minutes), plus unit tests for the taskbar arrangement, against a throwaway profile
and a temporary folder, with two plain test windows: window lists, tab groups and crash
recovery, the taskbar feed, hiding and restoring the Windows taskbar, the launcher,
palette, Home, intro, switcher, Files (rename, copy, paste, Recycle Bin, tab dragging),
toasts, and quitting cleanly. Test windows take focus and the Windows taskbar is hidden
for a few seconds, so leave the mouse and keyboard alone while it runs. Add
`-- --no-build` to skip the build.

The real shortcuts and mouse drags between windows cannot be scripted (the hooks ignore
simulated keys on purpose); `tests/MANUAL.md` lists those checks.

## Architecture

```
main.js            Electron main: windows, tray, settings, IPC, helper lifecycle
files-main.js      Files windows and their file system work
preload.js         contextBridge API surface for every page
renderer/          index (launcher and palette), home, switcher, tabstrip, taskbar,
                   files, toast: HTML/CSS/JS per surface, built to design/graphite
renderer/tokens.css  Generated from design/graphite/tokens.json by scripts/gen-tokens.js
design/            The Graphite design system: tokens, component specs and previews
helper/            WinKeyHelper: headless C# sidecar
scripts/           gen-icon.js (tray icon), gen-tokens.js (tokens.css)
```

### The C# helper

Electron cannot hook the keyboard system-wide, see other processes' windows in z-order,
or ask DWM for live previews, so the helper does that and streams JSON lines over stdio:

| file | job |
| --- | --- |
| `KeyboardHook.cs` | Win key, `Win+E`, `Alt+Space`, Alt+Tab. Swallowed keys are followed by a dummy key (VK `0xE8`) so Windows never sees a bare Win or Alt press. Injected input is ignored. |
| `StartWatcher.cs` | Notices the Windows Start menu opening (Start button, `Ctrl+Esc`). |
| `Indexer.cs` | Enumerates `shell:AppsFolder` and caches app icons as PNGs (alpha preserved). |
| `EmptyScreenWatcher.cs` | Reports when no app window is visible, for Home. |
| `WindowList.cs` | The Alt+Tab-eligible windows, their icons, activation and closing. |
| `Thumbnails.cs` | DWM previews for the switcher and the merge animation, drawn into an invisible overlay the helper owns (DWM only draws into the caller's own windows). |
| `TabGroups.cs` | Window tabs: drag detection, grouping, hiding, strip placement and stacking. |
| `Taskbar.cs` | Running windows from the shell hook, hiding and restoring the Windows taskbar, Win+A / Win+N. |

Electron registers its own shell surfaces (`shellwindow <hwnd>`) so the helper never
mistakes them for app windows; Files windows are not registered, so they behave like
any other app.

Commands and events are listed at the top of `helper/Program.cs`.

## Settings

`%AppData%/Graphite/settings.json` (dev mode: `%AppData%/graphite-dev`): pinned apps, labels, recents, density, which
pieces are on, and the crash-recovery records (`hiddenTabs`, `nativeTaskbar`). "Run at
startup" uses the per-user login item (HKCU Run key).

## Known limitations

- The Windows Start menu may flash briefly when opened via the taskbar Start button
  before ours replaces it.
- Other apps' tray icons stay in the Windows taskbar's notification area (use the
  chevron to see them). Native Windows notifications are not restyled: reading them
  needs a packaged (MSIX) app.
- Windows running as administrator cannot be hooked, hidden or moved by the helper
  unless it runs elevated too.
- Remote Desktop input is injected, which the hook ignores; RDP sessions get the
  normal Windows behaviour.
- Taskbar and Home use the primary display only.
