# Switcher

The window switcher that replaces Alt+Tab: every open window as a live preview card on one solid panel, over the `scrim`. It has to feel instant, so it does not rise in like the palette; it is simply there the moment Tab is pressed.

## Anatomy

- Panel: solid `surface-200`, `radius-lg`, `glass-edge`, `shadow-overlay`, `space-4` padding, centred on the display under the pointer. Never translucent.
- Cards: 220px wide, `radius-md`, `space-2` padding, `space-2` apart, wrapping into rows. Most recently used first.
  - Preview: 204 by 128, `surface-100`, `radius-sm`. The window's live picture, letterboxed to keep its shape. A minimised window shows its 32px app icon centred instead, with "Minimised" in `hint` `ink-muted` below it.
  - Caption: 16px app icon, the window title in `strip` style (`ink-muted`, `ink` when selected), ellipsis beyond one line; the app's identifier on the right in `identifier` style.
- Selected card: `accent-soft` fill, `ink` caption. Hover: `surface-300`.
- Hint line under the cards, centred, `hint` style with key chips: `Tab` Next, `Shift` `Tab` Back, `W` Close window, `Esc` Cancel.

## Behaviour

- `Alt+Tab` opens it with the previous window selected; `Alt+Shift+Tab` selects the last one.
- While `Alt` is held: `Tab` or arrows move, `W` closes the selected window, `Esc` cancels, `Enter` switches. Releasing `Alt` switches to the selected window, restoring it if minimised.
- Clicking a card switches to it.
- One window open: the switcher still shows, so the shortcut never feels broken.

## Motion

- Open: none (instant). The scrim fades in over `duration-fast` behind the panel.
- Selection: fill changes only, `duration-instant`.
- Close: panel and scrim disappear at once when switching, so the chosen window is never covered.
