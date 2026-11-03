# WindowMerge

How windows join and split: drag one window onto another's tab strip and it folds in as a tab; drag the tab out and it unfolds back into a window. The same motion for opening and closing keeps the whole shell feeling like one material.

- **Pick up:** the dragged window gets `shadow-overlay` and follows the pointer with no lag.
- **Hover over a tab strip:** the target strip lightens to `surface-300`, a slot tab appears at the end (dashed `line-strong` edge, `accent-soft` fill, the incoming name), and the dragged window drops just below the strip, scales to `merge-scale` and dims to 90% so the slot stays visible.
- **Drop:** the window shrinks straight into the slot tab, its corners rounding up as it goes, and fades out (`duration-merge`, `ease-enter`). The slot becomes a real tab and its contents fade in at `stagger`.
- **Drop elsewhere:** the window just stays where it was dropped.
- **Split out:** pull the tab down past 16px (or use Split out): the tab fades away while a window grows out of its exact position to full size (`duration-merge`, `ease-enter`).
- **Open and close:** same as Window: rise in from `scale-from`, shrink to 0.98 and fade out.

On Windows, merging is done by Groupy 2, WindowTabs or Files' own tab dragging, and each draws its own animation. This spec is the target for apps you build or can theme, and the reference when choosing between those tools.
