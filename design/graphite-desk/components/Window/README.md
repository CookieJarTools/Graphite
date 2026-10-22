# Window

The card every app window should read as: title strip, inset body, ghost actions, keyboard hint. Most apps cannot be fully restyled, so this is the target for apps you control (Terminal, Files, notes, web apps) and the reference for tab tools and Windhawk mods.

- Card: gradient `surface-200` to `surface-100`, 1px `glass-edge`, `radius-md`, `shadow-card`.
- Title strip: `strip-height`, `header`, `line` below. Glyph and "Title - App" in `strip` `ink-muted`; one action glyph right.
- Body: `space-10` inset. Context line `name`, headline `display`, copy `body`, `space-6` between blocks. Meta top-right in `hint` `ink-muted`.
- Actions: ghost buttons (`action` style, `radius-sm`, `surface-300` on hover), `space-2` apart, bottom-left.
- Hint: one line in `hint` style, `space-4` from the bottom.
- Optional round icon button (`icon-button`, `radius-full`, `surface-300`) floats `space-6` beside the card for "new".

## Motion

- Open: opacity 0 to 1, scale `scale-from` to 1, up by `rise`, `duration-base`, `ease-enter`.
- Close: opacity to 0, scale to 0.98, `duration-fast`, `ease-exit`.
- Windows draws its own open and close animation for native apps; keep "Animation effects" on and it lands close to this. This spec is exact for apps you build or theme.
