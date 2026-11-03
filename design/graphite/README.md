# Graphite

A minimal Windows 11 shell: soft graphite cards on a dark backdrop, no desktop, search first. Every window reads like a calm card: a thin title strip, generous inset content, quiet ghost actions and a keyboard hint at the foot.

## Principles

- **No desktop.** When nothing is open (or everything is minimised) you see Home: the backdrop and one centred search field, like a browser's new tab page. Files never live on the desktop.
- **Cards, not chrome.** Windows are rounded cards with a gentle top-to-bottom gradient (`surface-200` to `surface-100`), a 1px `glass-edge` and a soft `shadow-card`. No heavy borders, no coloured title bars.
- **Grey first, one signal.** The interface is neutral greys. `accent` only appears for the caret, an unread dot, a focused input outline or progress.
- **Quiet actions.** Buttons are ghost buttons: text only at rest, `surface-300` fill on hover. One row of them, bottom-left of the card.
- **Keyboard first.** Every card ends with a hint line in `hint` style (for example "Ctrl+K More actions"). Every daily action has a shortcut.
- **Remove before adding.** A tool earns its place by replacing something, not by adding a widget.

## Visual foundations

- **Colour.** Dark is primary; light mirrors it. Text uses `ink` or `ink-muted` only, both 4.5:1 or better on every surface in both themes. `danger` and `success` are states, and sit on `surface-100` or `surface-200`.
- **Backdrop.** `backdrop` with a large soft radial glow of `backdrop-glow` behind the centre. It is the Home screen and the wallpaper.
- **Card anatomy.**
  1. Title strip: `strip-height` 40px, `header` fill, `line` hairline below. App glyph (16px, `ink-muted`), then "Title - App" in `strip` style `ink-muted`; one optional action glyph on the right.
  2. Body: `space-10` inset. Sender or context line in `name` style, headline in `display`, copy in `body`. `space-6` between blocks. Meta (time, size) top-right in `hint` `ink-muted`.
  3. Actions: ghost buttons in `action` style, `space-2` apart.
  4. Hint line: `hint` style `ink-muted`, `space-4` from the bottom edge.
- **Type.** `sans` (Inter, falling back to Segoe UI Variable) everywhere except Terminal and code, which use `mono`.
- **Shape.** `radius-md` windows and toasts, `radius-lg` for search, palette and taskbar, `radius-full` for round icon buttons and dots.
- **Depth.** Two levels only: cards (`shadow-card`) and overlays (`shadow-overlay`). Acrylic blur (`blur-glass`) only on the taskbar and toasts.
- **Readable search.** The command palette is always solid `surface-200` (never translucent) and sits on a full-screen `scrim` that dims whatever is behind it, so its text never competes with a busy window.
- **Spacing.** A 4px grid. `space-2` is the snap gap between windows and from the screen edge.

## Density

Every list (Explorer, palette results, sidebars, settings) offers three densities, chosen per app and remembered: **Compact** (`row-compact`, one line), **Comfy** (`row-comfy`, the default) and **Spacious** (`row-spacious`, larger icons plus a second line of useful detail such as item count, dimensions or location). Spacing and type stay the same across densities; only row height, icon size and the detail line change.

## Motion

Calm and quick: things rise a little and settle, they never bounce, spin or zoom. Entering uses `ease-enter`, leaving uses `ease-exit`, and leaving is always faster than entering.

| moment | what moves | timing |
| --- | --- | --- |
| Sign-in intro | Backdrop glow blooms from the centre; greeting and date fade up `rise`; they fade away and Home search rises in, recent rows staggered | `duration-intro` total |
| Window opens | Opacity 0 to 1, scale `scale-from` to 1, up by `rise` | `duration-base`, `ease-enter` |
| Window closes | Opacity to 0, scale to 0.98 | `duration-fast`, `ease-exit` |
| Palette opens | `scrim` fades in; palette scales from `scale-from` and rises `rise`; result rows follow at `stagger` | `duration-base`, `ease-enter` |
| Palette closes | Palette and scrim fade together | `duration-fast`, `ease-exit` |
| Toast arrives | Slides in `slide` from the right and fades in; the stack below eases down | `duration-slow`, `ease-enter`; stack `ease-standard` |
| Toast leaves | Slides back out to the right and fades | `duration-fast`, `ease-exit` |
| Window merges into a tab | Dragged window drops under the target strip at `merge-scale`, a slot tab opens; on release it shrinks into the slot and fades | `duration-merge`, `ease-enter` |
| Tab splits out | A window grows from the tab's exact position to full size | `duration-merge`, `ease-enter` |
| Tab opens / closes | Drops in from scale 0.9 / fades and shrinks | `duration-base` in, `duration-fast` out |
| Hover | Fill changes only, no movement | `duration-instant` |

- Animate opacity and transform only; never width, height or blur.
- Only one thing makes an entrance at a time; secondary items stagger behind it.
- If Windows "Animation effects" is off (Settings > Accessibility > Visual effects), everything appears instantly and the intro is skipped.

## The shell, piece by piece

| piece | behaviour | component |
| --- | --- | --- |
| Intro | Plays once at sign-in, then hands over to Home. | Intro |
| Launcher | Start and full search in one panel: places, pinned apps, recent items, grouped results with identifiers, power actions. Opened with `Win` or `Alt+Space`. | Launcher |
| Home | Shown when no window is visible. Centred search field, recent items under it. Typing searches apps, files, settings and the web. | HomeSearch |
| Command palette | The compact, results-only form of the Launcher, on a dimming scrim. | CommandPalette |
| Windows | Floating cards that snap into zones; related windows group under tabs in the title strip. | Window, TabStrip |
| Taskbar | Floating, centred, `radius-lg`, auto-hides when a window is maximised. Open windows as labelled pills, tray and clock on the right. | Taskbar |
| Toasts | Top-right cards, `toast-width`, title strip plus one line and up to two ghost actions. | Toast |
| Files | Translucent sidebar, tabs in the top strip, path-and-search field, detail list with three densities. | Explorer |
| Merging windows | Drag a window onto another's tabs to fold it in; drag a tab out to split it. | WindowMerge |

## Identifiers, labels and keys

Borrowed from Linear and used everywhere a list shows things you can open:

- **Identifiers:** every app, folder, command and project file has a short id that doubles as a typed alias (`CL`, `DL`, `dark`, `LMS-142`). Always `identifier` type style (mono 11px), `ink-muted`, in a fixed-width column so they line up down a list.
- **Labels:** a 6px dot in one of five `tag-*` colours plus the label name in `ink-muted`, inside a hairline pill. Colour never stands alone.
- **Status glyphs:** a dashed ring for idle and a ring with a filled centre in `success` for running, instead of words where space is tight.
- **Key chips:** every shortcut shown as `key` chips (`key` fill, `glass-edge`, `key` type style, `key-height`), one chip per key.

## Iconography

Linear-style line icons: 16px on a 16px grid, 1.5px stroke, round caps and joins, no fills except status centres. Segoe Fluent Icons or Fluent System Icons outline are the closest built-in sets. Always `ink-muted`, `ink` on hover; 20px only in round icon buttons. App icons (the one place colour appears) sit on neutral `surface-100` tiles in the launcher, taskbar and search results, never loose.

## Tool stack

| role | tool |
| --- | --- |
| Home and power search | PowerToys Command Palette, opened automatically on an empty screen by the Home watcher script in `setup.md` |
| Instant file search | Everything (voidtools), feeding the palette |
| Window tabs | Groupy 2 (Stardock, paid) or WindowTabs (free, open source) |
| Snapping and layouts | PowerToys FancyZones and Workspaces |
| Taskbar | Native taskbar restyled with the Windhawk "Windows 11 Taskbar Styler" mod: floating, rounded, translucent |
| Toasts | Native notifications, restyled with Windhawk's notification styler mod where available; Focus mode for quiet hours |
| Files | Files (files.community): tabs, dual pane, Mica backdrop, custom theme. Native Explorer as fallback |
| Intro, Home, search scrim | `GraphiteShell.ahk` (in `setup.md`) |
| Terminal | Windows Terminal with the Graphite scheme |

## Usage rules

- One card style for every window; never mix in a coloured title bar.
- Accent on at most one element per card.
- Ghost buttons only; a filled button is reserved for a destructive confirm in `danger`.
- `ink-muted` never on `accent-soft`.
- Snap gap always `space-2`; windows never touch each other or the screen edge.
- No desktop icons, no widgets, no news, no Start recommendations.

`setup.md` has the install order, the Home watcher script and the config snippets.
