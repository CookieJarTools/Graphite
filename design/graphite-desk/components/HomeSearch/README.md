# HomeSearch

What you see instead of a desktop. When no window is visible, the Home watcher opens the command palette and the screen becomes one centred search field on the backdrop, like a browser's new tab page.

- Backdrop: `backdrop` with a `backdrop-glow` radial behind the centre. Nothing else on screen except the taskbar.
- Field: 560px wide, `radius-lg`, card gradient, `glass-edge`, `shadow-overlay`. Search glyph `ink-muted`, placeholder `ink-muted`, caret `accent`. Text in `name` style.
- Below it, up to six recent items as quiet rows in `body` with `hint` meta, no box around them.
- A `hint` line at the bottom of the screen lists the three most useful shortcuts.
- Typing turns the field into the full CommandPalette in place.

## Motion

- The field rises in by `rise` from `scale-from`, `duration-slow`, `ease-enter`.
- Recent label at 120ms, then each row at `stagger` (30ms) apart, `duration-base`.
- Shortcut line fades in last.
