# TabStrip

Grouped windows share one card; their tabs replace the title text in the title strip. Target styling for Groupy 2 or WindowTabs.

- Tabs sit inside the `header` strip, `strip-height` tall, starting `space-4` in.
- Active tab: `surface-200` pill, `radius-sm`, `ink` text in `strip` style, 1px `glass-edge`.
- Inactive tabs: no fill, `ink-muted`; `surface-300` on hover.
- Max 200px each, ellipsis beyond; close glyph only on hover.
- No accent on tabs: the active tab is shown by fill and ink, not colour.
