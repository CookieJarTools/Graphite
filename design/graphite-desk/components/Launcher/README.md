# Launcher

The Start menu and full search in one panel, opened with `Win` or `Alt+Space`. It borrows Linear's discipline: thin monochrome icons, a fixed identifier column, quiet label dots, status glyphs and keyboard chips everywhere.

## Anatomy

- Panel: `launcher-width`, solid `surface-200`, `radius-lg`, `glass-edge`, `shadow-overlay`, always over the `scrim`. Never translucent.
- Search row: 56px, 18px search glyph, placeholder "Search apps, files, folders and commands", `accent` caret, `Esc` key chip on the right.
- Scope bar: All, Apps, Files, Folders, Commands. Active scope `surface-100` with `glass-edge`. While searching, each scope shows its match count in `identifier` style. `Tab` and `Shift+Tab` cycle scopes.
- Footer on `header`: avatar and name on the left, context key hints in the middle, power actions on the right.

## Idle state (nothing typed)

1. **Places:** folder chips (AppData, Local, Temp, Home, Downloads). Holding `Alt` reveals their number keys; `Alt+1` to `Alt+5` open them.
2. **Pinned:** a grid of app tiles, `app-tile` neutral squares holding the app's own 24px icon, name below in 12px. A small `success` running dot sits on the tile's corner; the alias appears top-right on hover.
3. **Recent:** the last four apps or files as identifier rows (below).

## Searching

Results are grouped (Apps, Files, Folders, Commands), at most four per group in All, with a group header showing its total in `identifier` style. Each row reads left to right like a Linear issue row:

| column | content |
| --- | --- |
| kind | 16px monochrome glyph: app grid, file, folder or command prompt |
| identifier | fixed 56px column in `identifier` style: the alias (`CL`, `DL`, `dark`) or a project id for files (`LMS-142`) |
| icon | 20px mini tile: the app icon, or a glyph |
| name | `ink`, the matched characters in weight 600; a file or folder's path follows in `ink-muted` |
| label | category pill: 6px dot in a `tag-*` colour plus the name in `ink-muted` |
| status or keys | running state as a Linear-style status glyph (dashed ring idle, filled ring running), or a command's keyboard chips |
| meta | last used, right aligned |

- Arrow keys move the `accent-soft` selection; `Enter` opens; `Ctrl+Enter` runs as admin; `Esc` clears, then closes.
- An exact alias match always ranks first, so typing `CL` and `Enter` opens Claude.
- No results: one line offering `Enter` to search the web.

## Identifiers

Every launchable thing has a short identifier that doubles as a typed alias. Apps get two or three capital letters from their name, folders the same, commands a lowercase word, files the project key and number when they belong to a project. Identifiers are always mono, `ink-muted`, in their own fixed column so they line up.

## Labels

Five category labels, each a dot colour: Dev `tag-blue`, Media `tag-green`, Games `tag-violet`, Social `tag-rose`, System `tag-teal`. Colour is never the only cue: the label name is always written next to the dot.

## Power actions

Lock, Sign out, Sleep, Restart, Shut down as 16px icon buttons with a tooltip naming the action and its shortcut. Sign out, Restart and Shut down need a second press within three seconds: the button widens to "Press again to restart" with a `danger` outline.

## Motion

Opens like the CommandPalette: scrim fades in, panel rises by `rise` from `scale-from` over `duration-base`. Result rows fade in at 20ms `stagger` as you type; selection moves instantly. Opening an item gives its row a brief `accent-soft` pulse.

## Building it

If the launcher is your own app, this spec and the preview are directly implementable: the identifier, label and key-chip styles all come from `tokens.json`. If you use PowerToys Command Palette or Flow Launcher instead, match what their themes allow (solid surface, row height, font, selection colour) and use their alias or keyword features for identifiers.
