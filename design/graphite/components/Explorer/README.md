# Explorer

The file manager: a translucent full-height sidebar, tabs in the top strip, a quiet detail list with three densities. Target styling for Files (files.community); the same layout fits Settings, mail and any list-and-detail app.

## Layout

- Sidebar: `sidebar-width`, `sidebar` fill over Mica or acrylic so the wallpaper glows through, `glass-edge` on its right. App name at the top in `strip` weight 600. Collapsible sections (Quick access, Devices, Cloud) with a chevron that rotates; items `ink-muted`, the current one `ink` with a 2px `accent` marker on its left. No Desktop entry: there is no desktop.
- Top strip: `strip-height` on `header`. Tabs on the left, a plus for a new tab (`Ctrl+T`), window controls on the right.
- Toolbar: back and forward, one field that is both path and search (`surface-200`, `radius-sm`), the density switch, sort.
- Columns: Name, Type, Size (right aligned), Modified. Headers in `hint` `ink-muted` over a `line` hairline; no grid lines between rows.
- Footer: item count and the key shortcuts in `hint`.

## Density

Set with the switch in the toolbar and remembered per app. Applies to every list in the system (palette results, sidebars, settings rows), not only Explorer.

| density | row | icon | shows |
| --- | --- | --- | --- |
| Compact | `row-compact` 28px | `icon-list` | one line, tighter toolbar |
| Comfy (default) | `row-comfy` 36px | `icon-list` | one line |
| Spacious | `row-spacious` 56px | `icon-list-large` | a second line of detail: item count and location for folders, dimensions for images, folder path for files |

Switching density re-lays the list instantly and the rows fade in at `stagger`; row heights never animate.

## Tabs

- Active tab `surface-200` with `glass-edge`, `ink`; inactive `ink-muted`, `surface-300` on hover. Close glyph shows on hover and on the active tab.
- New tab: appears with a small drop and scale from 0.9 (`duration-base`, `ease-enter`). Closing: fades and shrinks (`duration-fast`, `ease-exit`) and the neighbour becomes active.
- Dragging another Explorer window onto the strip merges it in as a tab; dragging a tab out splits it into its own window. See WindowMerge.

## Files app settings that get closest

Theme dark, backdrop Mica (sidebar translucency), custom background `#232427`, tabs on, details layout with the Type, Size and Date modified columns. Use its compact or default spacing for Compact and Comfy.
