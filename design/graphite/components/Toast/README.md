# Toast

A notification as a small card, top-right, stacking downward with `space-2` gaps.

- `toast-width`, `radius-md`, card gradient, `glass-edge`, `shadow-card`, acrylic where supported.
- Mini title strip: app glyph and app name in `strip` `ink-muted`, time on the right in `hint`.
- Body: `space-4` inset. Title in `body` weight 600 `ink`, one or two lines of `body` `ink-muted`.
- Up to two ghost actions. No images except an avatar when a person sent it.
- Errors add a `danger` glyph before the title; never a red card.
- Auto-dismiss after 6 seconds unless hovered.

## Motion

- Arrive: slide in `slide` (24px) from the right while fading in, `duration-slow`, `ease-enter`. Toasts already shown ease down to make room (`ease-standard`).
- Leave: slide back out right and fade, `duration-fast`, `ease-exit`; the stack closes the gap smoothly.
- At most three visible; the oldest leaves when a fourth arrives. Hovering pauses auto-dismiss.
- Native Windows toasts use their own slide-in, which is close to this; the timing above is the target for anything you can style.
