-- Graphite Desk on Hyprland (0.55+, Lua config). linux/setup.sh links this file to
-- ~/.config/hypr/hyprland.lua; Hyprland reloads it on save.
--
-- The shell (Quickshell, linux/quickshell) draws the desktop, the bar, the launcher, Alt+Tab
-- and notifications; this file starts it, styles windows in the same Graphite look, and
-- hands it its keys as global shortcuts ("quickshell:<name>", see modules/Shortcuts.qml).

local shell = "qs -c graphite"

-- Title bars (below): Hyprland's hyprbars plugin, built for this version of Hyprland.
local titlebars = (os.getenv("HOME") or "") .. "/.local/share/graphite/hyprbars-" .. hl.version() .. ".so"
local function exists(path)
    local file = io.open(path)
    if file then file:close() end
    return file ~= nil
end

-- ---------- start-up ----------

hl.on("hyprland.start", function()
    -- First, the session's environment for what systemd and D-Bus start (the portals apps open
    -- files and links through): without them reaching the screen, apps wait half a minute.
    -- Password prompts are the shell's own (PasswordPrompt.qml): hyprpolkitagent's window crashed.
    hl.exec_cmd("dbus-update-activation-environment --systemd --all; systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_DATA_DIRS PATH; systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service; systemctl --user stop hyprpolkitagent")
    hl.exec_cmd(shell)
    -- Idle (lock, screen off, sleep: the Control Panel writes its settings) and startup apps.
    hl.exec_cmd("hypridle")
    -- Files, started in the background so its window opens at once when asked for.
    hl.exec_cmd("nautilus --gapplication-service")
    hl.exec_cmd("bash \"$HOME/.config/quickshell/graphite/../system/autostart.sh\"")
    -- Title bars (below): built the first time this version of Hyprland starts, as after an update.
    if not exists(titlebars) then
        hl.exec_cmd("bash \"$HOME/.config/quickshell/graphite/../hypr/titlebars/build.sh\" >/dev/null 2>&1 && hyprctl reload")
    end
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

-- Which desktop this is, for apps, Flatpak and the portals (which pick their helpers by it).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
-- Electron apps (Discord, VS Code...) drawn natively on Wayland.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- NVIDIA on Wayland, whenever its driver is loaded (Hyprland's wiki for 0.56). GTK 4 apps use
-- its OpenGL renderer: the Vulkan one hangs on NVIDIA and starts slower (Arch sets the same,
-- but in a profile script a desktop started by greetd doesn't read).
local nvidia = io.open("/sys/module/nvidia_drm/version")
if nvidia then
    nvidia:close()
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
    -- Apps drawn with WebKit (the Modrinth App, some installers) show a blank window otherwise.
    hl.env("WEBKIT_DISABLE_DMABUF_RENDERER", "1")
    hl.env("GSK_RENDERER", "ngl")
end

-- Apps installed from Flathub (theirs and everyone's), alongside the system's: the launcher
-- and the file manager find them by these folders.
local home = os.getenv("HOME") or ""
hl.env("XDG_DATA_DIRS", home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")
hl.env("PATH", home .. "/.local/bin:" .. (os.getenv("PATH") or "/usr/local/bin:/usr/bin"))

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

-- ---------- keyboard ----------

-- The layout chosen when installing (/etc/graphite/keyboard), else UK.
local keyboardLayout = "gb"
local keyboardFile = io.open("/etc/graphite/keyboard")
if keyboardFile then
    keyboardLayout = keyboardFile:read("l") or keyboardLayout
    keyboardFile:close()
end

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
        kb_layout = keyboardLayout,
        -- As on Windows: a window takes the keyboard when it is clicked, not when the pointer
        -- passes over it (the wheel still scrolls the one under the pointer). Otherwise the bar
        -- takes the last window crossed on the way down for the one in front.
        follow_mouse = 2,
        sensitivity = -0.4, -- calmer than libinput's own; the Control Panel changes it
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
        allow_session_lock_restore = true, -- a restarted shell takes the lock screen back over
        vrr = 2, -- variable refresh rate for fullscreen windows (games), where the screen has it
        -- An app asking to come forward (a link opened in the browser, a second start) does.
        focus_on_activate = true,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "0x141516", -- backdrop, should the shell not be running
    },

    -- VMware's cursor plane is unreliable; the cursor is drawn by Hyprland instead.
    cursor = {
        no_hardware_cursors = 1,
        -- The pointer stays where it is when a window is brought forward (from the bar, Alt+Tab).
        no_warps = true,
    },
})

-- ---------- title bars ----------

-- Apps that leave their title bar to the desktop (Kitty, GTK 3 dialogs, Qt apps) get one, as on
-- Windows: the title on the left, minimise, maximise and close on the right; drag it to move the
-- window, double-click it to maximise. It's Hyprland's hyprbars plugin, built for this version of
-- Hyprland by titlebars/build.sh (at start-up, above, when it isn't yet); apps that draw their own
-- title bar keep it, without a second one.
if exists(titlebars) then pcall(hl.plugin.load, titlebars) end
if hl.plugin.hyprbars then
    local maximise = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']]
    hl.config({
        plugin = {
            hyprbars = {
                bar_height = 32,
                bar_color = surface,
                col = { text = ink },
                bar_text_font = "Inter",
                bar_text_size = 11,
                bar_text_weight = "medium",
                bar_text_align = "left",
                bar_padding = 12,
                bar_button_padding = 12,
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                on_double_click = maximise,
            },
        },
    })
    -- Right to left. Minimised windows wait on the shell's "minimized" workspace (services/Taskbar.qml).
    local clear = "0x00000000"
    hl.plugin.hyprbars.add_button({ bg_color = clear, fg_color = ink, size = 16, icon = "✕", action = "hyprctl dispatch 'hl.dsp.window.close()'" })
    hl.plugin.hyprbars.add_button({ bg_color = clear, fg_color = ink, size = 16, icon = "□", action = maximise })
    hl.plugin.hyprbars.add_button({ bg_color = clear, fg_color = ink, size = 16, icon = "—", action = [[hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:minimized", follow = false })']] })
    -- Steam draws its own and doesn't say so.
    hl.window_rule({ match = { class = "^steam$" }, ["hyprbars:no_bar"] = true })
    -- Nor do the apps whose bar was hidden from the taskbar's menu (Taskbar.setTitleBar).
    local hidden = io.open((os.getenv("HOME") or "") .. "/.config/graphite/no-titlebar")
    if hidden then
        for app in hidden:lines() do
            if app ~= "" then
                local exact = "^" .. app:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?{}|\\]", "\\%0") .. "$"
                hl.window_rule({ match = { class = exact }, ["hyprbars:no_bar"] = true })
            end
        end
        hidden:close()
    end
end

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
    hl.window_rule({ match = { class = ".*" }, float = true })
    -- Centred, but not X11 menus (Steam's: windows without a title), which open where the app puts them.
    hl.window_rule({ match = { xwayland = false }, center = true })
    hl.window_rule({ match = { xwayland = true, title = ".+" }, center = true })
end

-- Games (Steam and Proton, Minecraft): frames go out as soon as they are drawn (tearing
-- allowed), for the least input lag.
hl.window_rule({ match = { class = "^(steam_app_.*|Minecraft.*|minecraft.*|gamescope)$" }, immediate = true })

-- Animations as quick as Windows' (speed is in tenths of a second; Hyprland's own fallback is
-- most of a second), on the design's curves: ease-enter for what arrives, ease-exit for what goes.
hl.curve("enter", { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })
hl.curve("exit", { type = "bezier", points = { {0.4, 0}, {1, 1} } })
hl.animation({ leaf = "global", enabled = true, speed = 2.2, bezier = "enter" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.2, bezier = "enter", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "exit", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "enter" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.8, bezier = "enter" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "exit" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.6, bezier = "enter", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "exit", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2.4, bezier = "enter", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1.6, bezier = "enter" })

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

-- The shell: the Super key alone opens the launcher (pressed and let go with nothing else in
-- between, as on Windows: watched in the keyboard event below, as a release bind on the key
-- never goes off); Alt+Tab switches windows; Ctrl+Shift+Esc opens the task manager.
hl.bind("ALT + Tab", hl.dsp.global("quickshell:switcher-next"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.global("quickshell:switcher-previous"))
hl.bind("ALT_L", hl.dsp.global("quickshell:switcher-commit"), { release = true })
hl.bind("ALT + space", hl.dsp.global("quickshell:palette"))
hl.bind("SUPER + L", hl.dsp.global("quickshell:lock"))

-- Window zones (Shift + drag a window, Ctrl to span): the shell hears the left button go down
-- and up (a bind that does not take the click from apps), and Shift and Ctrl from the keyboard
-- event below. Not binds for those: a bind going off in the middle of a drag ends the drag.
local passOn = { non_consuming = true, ignore_mods = true }
local passOnRelease = { non_consuming = true, ignore_mods = true, release = true }
local superAlone = false -- Super is down and nothing else has been pressed with it
hl.bind("mouse:272", hl.dsp.global("quickshell:pointer-down"), passOn)
hl.bind("mouse:272", hl.dsp.global("quickshell:pointer-up"), passOnRelease)
-- Super + drag moves a window; letting go of Super after it opens nothing.
hl.bind("mouse:272", function() superAlone = false end, passOn)
hl.bind("mouse:273", function() superAlone = false end, passOn)

local superKeys = { [133] = true, [134] = true } -- XKB codes, left and right
local modifierKeys = { [50] = "shift", [62] = "shift", [37] = "ctrl", [105] = "ctrl" }
local modifierState = { shift = false, ctrl = false }
hl.on("input.keyboard.key", function(keycode, _, state)
    local down = state == 1
    if superKeys[keycode] then
        if down then
            superAlone = true
        elseif superAlone then
            superAlone = false
            hl.exec_cmd(shell .. " ipc call launcher toggle")
        end
        return
    end
    if down then superAlone = false end
    local name = modifierKeys[keycode]
    if not name then return end
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
hl.bind("SUPER + grave", hl.dsp.group.next())
hl.bind("SUPER + SHIFT + grave", hl.dsp.group.prev())
hl.bind("SUPER + CTRL + O", hl.dsp.window.move({ out_of_group = true }))

-- Workspaces 1 to 9
for number = 1, 9 do
    hl.bind("SUPER + " .. number, hl.dsp.focus({ workspace = tostring(number) }))
    hl.bind("SUPER + SHIFT + " .. number, hl.dsp.window.move({ workspace = tostring(number) }))
end

-- Mouse: Super + drag moves a window, Super + right-drag resizes it.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots and recordings, as on Windows: Print and Super+Shift+S open the Snipping Tool
-- (modules/CaptureTool.qml), Super+Shift+R opens it to record, or stops the recording. Its
-- surfaces come and go without fading: the still of the screen it opens over appears at once,
-- and nothing of it is left on the screen when the picture is taken.
hl.bind("Print", hl.dsp.global("quickshell:capture"))
hl.bind("SUPER + SHIFT + S", hl.dsp.global("quickshell:capture"))
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:capture-record"))
hl.layer_rule({ match = { namespace = "graphite-capture.*" }, no_anim = true })

-- Super+Tab: task view, every window and desktop, as on Windows.
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:taskview"))

-- Ctrl+Shift+Esc: the task manager, as on Windows.
hl.bind("CTRL + SHIFT + Escape", hl.dsp.global("quickshell:taskmanager"))

-- ---------- the Control Panel's choices ----------

-- Screens, the mouse and touchpad, and the keyboard layout as chosen in the Control Panel
-- (services/Displays.qml writes this file), over everything above.
local desk = loadfile((os.getenv("HOME") or "") .. "/.config/graphite/desk.lua")
if desk then pcall(desk) end
