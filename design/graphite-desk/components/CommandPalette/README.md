# CommandPalette

HomeSearch summoned over open windows with `Alt+Space`. Style reference for PowerToys Command Palette.

- Container: 640px, `radius-lg`, solid `surface-200`, `glass-edge`, `shadow-overlay`. No acrylic.
- Input row: `name` style, `space-6` side padding, `line` hairline below, caret `accent`.
- Results: `body` rows, `radius-sm`, `space-2` vertical padding. Selected row `accent-soft` with `ink` text; hover `surface-300`.
- Kind and shortcut on the right in `hint` `ink-muted`.
- Footer hint line: Enter to open, Ctrl+Enter to open folder, Ctrl+K actions.

## Background and motion

- The palette is solid `surface-200`, never translucent, on a full-screen `scrim` so text stays readable over any window.
- Open: scrim fades in while the palette rises by `rise` from `scale-from`, `duration-base`, `ease-enter`; rows follow at `stagger`.
- Close (Esc, Enter or click away): palette and scrim fade together, `duration-fast`, `ease-exit`.
- On Windows the scrim is drawn by `GraphiteShell.ahk`; it is skipped on the Home screen, where nothing sits behind the palette.
