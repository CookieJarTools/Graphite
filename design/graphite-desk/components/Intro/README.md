# Intro

The sign-in moment: the screen goes from nothing to Home search in about 1.6 seconds, then gets out of the way.

- 0 to 900ms: `backdrop-glow` blooms from the centre (scale 0.6 to 1, `ease-enter`).
- 100 to 1100ms: greeting ("Good afternoon, Joe") in `display` and the date in `body` `ink-muted` fade up by `rise`, hold, then drift up and out.
- 1000ms: Home search rises in (`duration-slow`, `ease-enter`); the Recent label and rows follow at `stagger`.
- Plays once per sign-in, never on unlock or when returning to Home.
- Skipped entirely when Windows animation effects are off.
- On Windows this is drawn by the intro part of `GraphiteShell.ahk` (see `setup.md`): a backdrop overlay that matches the wallpaper, a fading greeting, then the command palette.
