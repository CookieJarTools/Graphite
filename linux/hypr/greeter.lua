-- The login screen's Hyprland: just enough to show Graphite's greeter (quickshell/greeter.qml)
-- on every screen, run by greetd as the "greeter" user (/etc/greetd/config.toml, written by
-- the installer). When someone signs in, the greeter hands over to their own desktop and this
-- Hyprland leaves with it.

-- Where Graphite Desk lives: the repository in /opt/graphite-desk on an installed machine, the
-- shared checkout in the test VM.
local home = "/opt/graphite-desk/linux"
if not io.open(home .. "/quickshell/greeter.qml") then home = "/mnt/StartMenu/linux" end

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p " .. home .. "/quickshell/greeter.qml; hyprctl dispatch 'hl.dsp.exit()'")
end)

hl.env("XCURSOR_THEME", "capitaine-cursors-light")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")

-- The same keyboard as the desktop (the installer writes it), else UK.
local layout = "gb"
local keyboard = io.open("/etc/graphite/keyboard")
if keyboard then
    layout = keyboard:read("l") or layout
    keyboard:close()
end

-- In VirtualBox the shell draws in software (see hyprland.lua).
local vendor = io.open("/sys/class/dmi/id/sys_vendor")
if vendor then
    if vendor:read("l") == "innotek GmbH" then hl.env("LIBGL_ALWAYS_SOFTWARE", "1") end
    vendor:close()
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
    input = { kb_layout = layout },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "0x141516",
    },
    animations = { enabled = false },
    cursor = { no_hardware_cursors = 1 },
})
