-- The installer's Hyprland on the USB stick: just enough to show Graphite's installer screens
-- (quickshell/installer.qml), run by graphite-install-gui as the stick's "live" user. When the
-- installer closes, this Hyprland leaves with it (and graphite-install-gui decides what next).

local home = "/usr/share/graphite-desk/linux"

hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p " .. home .. "/quickshell/installer.qml; touch /tmp/graphite-gui-closed; hyprctl dispatch 'hl.dsp.exit()'")
end)

hl.env("XCURSOR_THEME", "capitaine-cursors-light")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")

-- In VirtualBox the screens draw in software (see hyprland.lua).
local vendor = io.open("/sys/class/dmi/id/sys_vendor")
if vendor then
    if vendor:read("l") == "innotek GmbH" then hl.env("LIBGL_ALWAYS_SOFTWARE", "1") end
    vendor:close()
end

-- NVIDIA's driver loaded (the stick has it for RTX cards): its settings for Wayland.
local nvidia = io.open("/sys/module/nvidia_drm/version")
if nvidia then
    nvidia:close()
    hl.env("LIBVA_DRIVER_NAME", "nvidia")
    hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
    hl.env("NVD_BACKEND", "direct")
end

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
    input = { kb_layout = "gb" },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        background_color = "0x141516",
    },
    animations = { enabled = false },
    cursor = { no_hardware_cursors = 1 },
})
