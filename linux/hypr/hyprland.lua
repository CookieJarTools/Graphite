-- Graphite Desk on Hyprland (0.55+, Lua config). linux/setup.sh links this file to
-- ~/.config/hypr/hyprland.lua; Hyprland reloads it on save.
--
-- The shell (Quickshell, linux/quickshell) draws the desktop, the bar, the launcher, Alt+Tab
-- and notifications; this file starts it, styles windows in the same Graphite look, and
-- hands it its keys as global shortcuts ("quickshell:<name>", see modules/Shortcuts.qml).

local shell = "qs -c graphite"

-- ---------- start-up ----------

hl.on("hyprland.start", function()
    hl.exec_cmd(shell)
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    -- The VM's guest tools: shared clipboard and resizing with the window (VirtualBox or VMware).
    hl.exec_cmd("command -v VBoxClient-all >/dev/null && VBoxClient-all; command -v vmware-user >/dev/null && vmware-user")
end)

-- ---------- environment ----------

-- The pointer: Capitaine (light), cleaner resize shapes than Adwaita's (linux/gtk/apply.sh
-- sets the same for apps).
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "capitaine-cursors-light")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")

-- In VirtualBox, Hyprland itself draws on the virtual GPU, but the GPU buffers apps hand it
-- are refused ("invalid arguments for wl_surface.attach") and the app is disconnected, so
-- apps (the shell among them) draw with Mesa's software GL instead.
-- Text, the MacType way: FreeType's stem darkening gives smoother, fuller strokes (with
-- fonts/fonts.conf). Settings' "Smoother text" writes "standard" to ~/.config/graphite/text
-- to turn it off; apps opened afterwards follow.
local text = io.open((os.getenv("HOME") or "") .. "/.config/graphite/text")
local textMode = text and text:read("l") or "smooth"
if text then text:close() end
if textMode ~= "standard" then
    hl.env("FREETYPE_PROPERTIES", "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 type1:no-stem-darkening=0 t1cid:no-stem-darkening=0")
end

-- NVIDIA on Wayland (linux/gaming.sh writes "nvidia" here when it finds one).
local gpu = io.open((os.getenv("HOME") or "") .. "/.config/graphite/gpu")
if gpu then
    if gpu:read("l") == "nvidia" then
        hl.env("LIBVA_DRIVER_NAME", "nvidia")
        hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
        hl.env("NVD_BACKEND", "direct")
    end
    gpu:close()
end

local inVirtualBox = false
local vendor = io.open("/sys/class/dmi/id/sys_vendor")
if vendor then
    inVirtualBox = vendor:read("l") == "innotek GmbH"
    vendor:close()
end
if inVirtualBox then
    hl.env("LIBGL_ALWAYS_SOFTWARE", "1")
end

-- ---------- screens ----------

-- Every screen at its preferred size and scale 1 (Hyprland's guess for a VM window is 2).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- ---------- look: Graphite (design/graphite-desk/tokens.json) ----------

local accent = "0xffe3ab4f"        -- accent
local edge = "0xff35363a"          -- line
local surface = "0xff2e2f32"       -- surface-200
local surfaceRaised = "0xff3b3c40" -- surface-300
local ink = "0xffededec"           -- ink
local inkMuted = "0xffa6a7aa"      -- ink-muted

hl.config({
    general = {
        gaps_in = 4,       -- space-1
        gaps_out = 8,      -- space-2: the snap gap between windows
        border_size = 1,
        resize_on_border = true,
        layout = "dwindle",
        allow_tearing = true, -- only for windows with the "immediate" rule: games (below)
        col = {
            active_border = accent,
            inactive_border = edge,
        },
    },

    decoration = {
        rounding = 12,     -- radius-md
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size = 8,
            passes = 2,
        },
        shadow = {
            enabled = true,
            range = 32,    -- shadow-card: soft and wide
            render_power = 3,
            color = "0x47000000",
        },
    },

    animations = {
        enabled = true,
    },

    input = {
        kb_layout = "gb",
        follow_mouse = 1,
    },

    -- Window tabs are Hyprland's groups, drawn as a strip of titles over the window. As on
    -- Windows: drag a window by its title onto another to make them tabs, drag a tab off the
    -- strip to pull it out; a middle click on a tab closes it.
    group = {
        drag_into_group = 1,
        merge_groups_on_drag = true,
        merge_floated_into_tiled_on_groupbar = true,
        insert_after_current = true,
        col = {
            border_active = accent,
            border_inactive = edge,
        },
        groupbar = {
            enabled = true,
            height = 22,
            font_family = "Inter",
            font_size = 11,
            font_weight_active = "semibold",
            render_titles = true,
            middle_click_close = true,
            gradients = true,
            gradient_rounding = 6, -- radius-sm
            rounding = 6,
            indicator_height = 0,
            gaps_in = 4,
            gaps_out = 4,
            text_color = ink,
            text_color_inactive = inkMuted,
            col = {
                active = surfaceRaised,
                inactive = surface,
            },
        },
    },

    misc = {
        vrr = 2, -- variable refresh rate for fullscreen windows (games), where the screen has it
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "0x141516", -- backdrop, should the shell not be running
    },

    -- VMware's cursor plane is unreliable; the cursor is drawn by Hyprland instead.
    cursor = {
        no_hardware_cursors = 1,
    },
})

-- Windows behave as on Windows: every one floats, opening centred at the size it asks for,
-- moved by its title bar (or Super + drag) and resized from its edges. Super + arrows snap it
-- to a half of the screen or maximise it (Shortcuts.qml, "snap"). The shell's "Tile windows"
-- setting writes "tiling" to ~/.config/graphite/windows and reloads this file; then new
-- windows tile instead.
local function windowMode()
    local file = io.open((os.getenv("HOME") or "") .. "/.config/graphite/windows")
    if not file then return "floating" end
    local mode = file:read("l")
    file:close()
    return mode == "tiling" and "tiling" or "floating"
end

if windowMode() == "floating" then
    hl.window_rule({ match = { class = ".*" }, float = true, center = true })
end

-- Games (Steam and Proton, Minecraft): frames go out as soon as they are drawn (tearing
-- allowed), for the least input lag.
hl.window_rule({ match = { class = "^(steam_app_.*|Minecraft.*|minecraft.*|gamescope)$" }, immediate = true })

-- In VirtualBox everything is drawn by the CPU (see LIBGL_ALWAYS_SOFTWARE above), so the
-- costly effects go: blur, shadows and Hyprland's own window animations. Real hardware keeps them.
if inVirtualBox then
    hl.config({
        decoration = { blur = { enabled = false }, shadow = { enabled = false } },
        animations = { enabled = false },
    })
end

-- The shell's surfaces: blur behind the see-through ones, nothing behind fully clear pixels.
hl.layer_rule({ match = { namespace = "graphite-(panel|menu|toasts|launcher|switcher)" }, blur = true, ignore_alpha = 0.5 })

-- ---------- keys ----------

local terminal = "kitty"
local files = "nautilus"

-- The shell: the Super key alone opens the launcher; Alt+Tab switches windows.
hl.bind("SUPER_L", hl.dsp.global("quickshell:launcher"), { release = true })
hl.bind("ALT + Tab", hl.dsp.global("quickshell:switcher-next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("quickshell:switcher-previous"))
hl.bind("ALT_L", hl.dsp.global("quickshell:switcher-commit"), { release = true })
hl.bind("ALT + space", hl.dsp.global("quickshell:palette"))
hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"))

-- Window zones (Shift + drag a window, Ctrl to span): the shell hears the left button go down
-- and up (a bind that does not take the click from apps), and Shift and Ctrl from the keyboard
-- event below. Not binds for those: a bind going off in the middle of a drag ends the drag.
local passOn = { non_consuming = true, ignore_mods = true }
local passOnRelease = { non_consuming = true, ignore_mods = true, release = true }
hl.bind("mouse:272", hl.dsp.global("quickshell:pointer-down"), passOn)
hl.bind("mouse:272", hl.dsp.global("quickshell:pointer-up"), passOnRelease)

local modifierKeys = { [50] = "shift", [62] = "shift", [37] = "ctrl", [105] = "ctrl" } -- XKB codes
local modifierState = { shift = false, ctrl = false }
hl.on("input.keyboard.key", function(keycode, _, state)
    local name = modifierKeys[keycode]
    if not name then return end
    local down = state == 1
    if modifierState[name] == down then return end -- held keys repeat
    modifierState[name] = down
    hl.exec_cmd("qs -c graphite ipc call zones " .. name .. " " .. tostring(down))
end)

-- Apps
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(files))

-- Windows
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + V", hl.dsp.window.float())
-- Super + arrows snap as on Windows: halves, maximise, restore or minimise (the shell does it).
hl.bind("SUPER + left", hl.dsp.global("quickshell:snap-left"))
hl.bind("SUPER + right", hl.dsp.global("quickshell:snap-right"))
hl.bind("SUPER + up", hl.dsp.global("quickshell:snap-up"))
hl.bind("SUPER + down", hl.dsp.global("quickshell:snap-down"))
hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "l", group_aware = true }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "r", group_aware = true }))
hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "u", group_aware = true }))
hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "d", group_aware = true }))

-- Window tabs (groups): make or break up a group, step through its tabs, pull one out.
hl.bind("SUPER + G", hl.dsp.group.toggle())
hl.bind("SUPER + Tab", hl.dsp.group.next())
hl.bind("SUPER + SHIFT + Tab", hl.dsp.group.prev())
hl.bind("SUPER + CTRL + O", hl.dsp.window.move({ out_of_group = true }))

-- Workspaces 1 to 9
for number = 1, 9 do
    hl.bind("SUPER + " .. number, hl.dsp.focus({ workspace = tostring(number) }))
    hl.bind("SUPER + SHIFT + " .. number, hl.dsp.window.move({ workspace = tostring(number) }))
end

-- Mouse: Super + drag moves a window, Super + right-drag resizes it.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
