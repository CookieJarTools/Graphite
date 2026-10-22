# Manual checks

`npm run test:e2e` covers everything a script can drive. What is left needs real keys
(the hooks ignore simulated ones on purpose) or a real mouse dragging between windows.

Start everything:

```bash
npm run dev -- --palette --alttab --tabs --home --taskbar --files
```

Then tick **Replace Windows Start menu** in the tray. If anything gets stuck,
`Ctrl+Alt+Shift+Q` quits and puts everything back.

## Keys

| # | Do | Expect |
| --- | --- | --- |
| 1 | Press and release **Win** | The launcher opens; the Windows Start menu does not |
| 2 | **Win+R**, **Win+Shift+S** | Run and Snipping Tool open as normal |
| 3 | In any app, **Alt+Space** | The palette opens; the app's window menu does not appear when Alt is released |
| 4 | Hold **Alt**, tap **Tab** a few times, release | The switcher shows live previews, the selection moves, releasing switches to it |
| 5 | Alt+Tab, then **W** while still holding Alt | The selected window closes and its card goes |
| 6 | Alt+Tab, then **Esc** | Nothing switches |
| 7 | **Alt+Shift+Tab** | Starts on the last window |
| 8 | **Win+E** | Files opens (not Explorer), and Start does not open on release |

## Mouse

| # | Do | Expect |
| --- | --- | --- |
| 9 | Drag a window by its title bar over another window's title bar | A strip with a dashed slot tab appears above the target |
| 10 | Let go there | The window shrinks into the slot; the group shows one window with two tabs |
| 11 | Click the other tab, then its **x**, then drag the strip | Switches, closes, moves the group |
| 12 | Pull a tab down out of the strip | It splits back into its own window |
| 13 | In Files, drag a tab along the strip, then pull it out | It follows the pointer, then floats outside the window |
| 14 | Drop it on another Files window's tabs | The slot stays steady while you move; the tab moves there |
| 15 | Drag a whole Files window by its title strip onto another | All its tabs fold in |
| 16 | Click a taskbar pill; click it again | Focuses the window, then minimises it |
| 17 | Maximise a window; push the pointer to the bottom edge | The bar hides, then slides back while the pointer is there |
| 18 | Click the clock, the status glyphs, the chevron | Notifications, Quick Settings; the chevron shows the Windows taskbar until you move away from it |
| 18a | Hover a running pill | After a moment, live previews of its windows; click one to switch |
| 18b | Drag a pill along the bar; then drag one and hold it on another | Reorders; holding highlights the target and letting go makes a folder, with its name ready to type |
| 18c | Right-click a pill, Pin to taskbar; close the app | The pill stays, dimmed; clicking it starts the app |
| 18d | Right-click the bar: Show app names off, Pin category > Dev | Icons only; a Dev folder holding your Dev-labelled apps |
| 18e | WhatsApp (or another Store app) running | Its real icon on the bar and in Alt+Tab |
| 18f | Hover a pill, then move the pointer quickly off the bar and away | The previews close on their own within a second |
| 18g | Hover an app with a minimised window | That window's card shows its icon and "Minimised" |
| 18h | Make a folder and type a name | The field is tinted and outlined in the accent colour, and the pill on the bar shows the name as you type |
| 18i | Right-click a combined pill (an app with several windows), Show windows separately; then Group windows | Its windows split into their own pills, then join back into one |

## Screen

| # | Do | Expect |
| --- | --- | --- |
| 19 | **Win+M** (minimise everything) | Home appears with the search field focused |
| 20 | Type, then open something | Home turns into the launcher in place, then hides as the window opens |
| 21 | Tray, **Play intro** | Greeting, then Home rises in |
| 22 | Tray, **Test toast** | A card slides in at the top right, leaves after 6 s (stays while hovered) |

Note anything that looks or feels off, even if it technically works.
