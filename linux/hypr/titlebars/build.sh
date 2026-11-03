#!/usr/bin/env bash
# Title bars with minimise, maximise and close, dragged to move the window, for the apps that
# leave their title bar to the desktop (Kitty, GTK 3 dialogs, Qt apps): Hyprland's own hyprbars
# plugin (github.com/hyprwm/hyprland-plugins), built here for the Hyprland installed, with
# Graphite's additions (graphite-decorations.cpp: no bar on windows that draw their own;
# graphite-drags.cpp: X11 apps that draw their own title bar, as Steam does, are dragged by it,
# and a drag keeps going when Shift or Ctrl goes down, for window zones; graphite-minimize.cpp:
# apps' own minimise buttons work; graphite-fonts.cpp: font settings changed since Hyprland
# started apply when the plugin loads; and a fix for the bar's background vanishing while a
# notification is up).
# hyprland.lua loads it when it was built for the running Hyprland; hyprland.lua's start-up and
# the person's updates (system/user-update.sh) run this when it wasn't, as after an update.
#
#   build.sh    prints the plugin's path once it's built
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
version="$(pkg-config --modversion hyprland)"
out="${XDG_DATA_HOME:-$HOME/.local/share}/graphite/hyprbars-$version.so"
# Built already, from these same additions and for this same Hyprland. Arch rebuilds Hyprland
# against new libraries without changing its version, and a plugin built before that refuses
# to load ("Version mismatch"), so the libraries' versions count too.
deps="$(pkg-config --modversion hyprland aquamarine hyprutils hyprlang hyprgraphics hyprcursor 2>/dev/null || true)"
stamp="$( { cat "$here"/build.sh "$here"/graphite-*; echo "$deps"; } | sha256sum | cut -d' ' -f1)"
if [ -f "$out" ] && [ "$(cat "$out.stamp" 2>/dev/null)" = "$stamp" ]; then
    echo "$out"
    exit 0
fi
for tool in g++ make git pkg-config; do
    command -v "$tool" >/dev/null || { echo "Building title bars needs $tool." >&2; exit 1; }
done

src="${XDG_CACHE_HOME:-$HOME/.cache}/graphite/hyprland-plugins"
export GIT_TERMINAL_PROMPT=0
if [ -d "$src/.git" ]; then
    timeout 120 git -C "$src" fetch -q origin </dev/null || true
else
    mkdir -p "$(dirname "$src")"
    timeout 300 git clone -q https://github.com/hyprwm/hyprland-plugins.git "$src" </dev/null
fi
# The commit hyprpm pins for this Hyprland ("# 0.56.2" after it), else the newest.
commit="$(grep -E "# $version\$" "$src/hyprpm.toml" 2>/dev/null | grep -oE '"[0-9a-f]{40}"' | tail -1 | tr -d '"' || true)"
commit="${commit:-origin/HEAD}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$src" archive "$commit" hyprbars | tar -x -C "$work"
cd "$work/hyprbars"
cp "$here"/graphite-* .
# No bar where the window draws its own: hidden as by the no_bar rule.
sed -i 's/^void CHyprBar::updateRules() {/bool graphiteWantsServerTitleBar(PHLWINDOW window);\n\n&/' barDeco.cpp
sed -i '/m_hidden = truthy(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->nobarRuleIdx)->effect);/a\    if (!graphiteWantsServerTitleBar(PWINDOW))\n        m_hidden = true;' barDeco.cpp
# The rounded corners' stencil, cleared with its writes allowed: Hyprland's blur (behind a
# notification) can leave them off, and the stale stencil then hid the bar's background.
sed -i 's/^\( *\)glClearStencil(0);/\1glStencilMask(-1);\n\1glClearStencil(0);/' barDeco.cpp
# Drags, from the plugin's start.
sed -i 's/^APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {/void graphiteHookDrags(HANDLE handle);\nvoid graphiteHookMinimize(HANDLE handle);\nvoid graphiteReloadFonts();\n\n&/' main.cpp
sed -i 's/^    return {"hyprbars",/    graphiteHookDrags(PHANDLE);\n    graphiteHookMinimize(PHANDLE);\n    graphiteReloadFonts();\n\n&/' main.cpp
grep -q 'graphiteWantsServerTitleBar(PWINDOW)' barDeco.cpp && grep -q '^    graphiteReloadFonts();' main.cpp &&
    [ "$(grep -c 'glStencilMask(-1);' barDeco.cpp)" -ge 3 ] ||
    { echo "hyprbars has changed: Graphite's additions no longer fit." >&2; exit 1; }
make -s SRC="main.cpp barDeco.cpp BarPassElement.cpp graphite-decorations.cpp graphite-drags.cpp graphite-minimize.cpp graphite-fonts.cpp" \
    INCLUDES="$(pkg-config --cflags pixman-1 libdrm hyprland libinput libudev wayland-server xkbcommon pangocairo fontconfig)" \
    LIBS="$(pkg-config --libs pangocairo fontconfig)" >&2
mkdir -p "$(dirname "$out")"
install -m 644 hyprbars.so "$out"
echo "$stamp" > "$out.stamp"
echo "$out"
