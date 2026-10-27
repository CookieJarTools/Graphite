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
    hl.exec_cmd("vmware-user") -- VMware: shared clipboard and resizing with the window
end)

-- ---------- environment ----------

hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("QT_QPA_PLATFORM", "wayland")

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

    -- Window tabs are Hyprland's groups, drawn as a strip of titles over the window.
    group = {
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
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "0x141516", -- backdrop, should the shell not be running
    },

    -- VMware's cursor plane is unreliable; the cursor is drawn by Hyprland instead.
    cursor = {
        no_hardware_cursors = 1,
    },
})

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

-- Apps
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(files))

-- Windows
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind("SUPER + V", hl.dsp.window.float())
hl.bind("SUPER + left", hl.dsp.focus({ direction = "l" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "u" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "d" }))
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
