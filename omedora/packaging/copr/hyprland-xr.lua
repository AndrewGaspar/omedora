-- Omedora XR configuration (Lua)
--
-- HypXRland's OpenXR directives in Quattro's Lua front end. This file is the
-- main config for the "Omedora XR" session: it pulls in your normal desktop
-- (theme, bindings, monitors, autostart) and layers the OpenXR extension on
-- top. Adjust the GPU, monitor, and XR placement below for this machine.
--
-- Created absent-only by omarchy-setup-hypxrland from the packaged template;
-- your copy is never overwritten.

-- Everything from the regular session. This requires your main Omarchy config
-- to also be Lua (~/.config/hypr/hyprland.lua); require() resolves against
-- this file's own directory.
require("hyprland")

hl.config({
  openxr = {
    enabled = true,
    overlay = true,
    hand_input = "off",
    depth_desktop = true,

    -- The OpenXR runtime and compositor must render on the same GPU.
    -- Uncomment and adjust after identifying the correct render node.
    -- gpu = "/dev/dri/renderD128",
  },
})

-- A usable first monitor that can be repositioned live with the XR controls.
hl.xr_monitor({
  name = "XR-main",
  mode = "2560x1440@90",
  anchor = "local",
  pos = { 0, 1.4, -1.5 },
  adaptive = true,
  roam = "body",
  size = 2.2,
})

-- Pin the declared mode as a persistent monitor rule (survives plug cycles).
hl.monitor({ output = "XR-main", mode = "2560x1440@90", position = "auto", scale = "1.25" })

-- XReal in 3D personality: uncomment to assert the SBS pack on the glasses
-- panel (in 2D personality the mode does not exist, so this stays inert).
-- hl.monitor({ output = "desc:Nreal Air 2 Ultra 0x88888800", mode = "3840x1080@60",
--   position = "auto", scale = "1", stereo = "sbs" })

-- exec-once has no keyword form in Lua: a config is re-run from the top on
-- every reload. Once-per-session autostart rides the hyprland.start event.
hl.on("hyprland.start", function()
  -- WiVRn streaming server for this session (pair headsets with `wivrnctl`).
  hl.exec_cmd("systemctl --user start wivrn.service")

  -- hypxrva watcher: yields hardware video decode to WiVRn's encode while a
  -- headset is donned.
  hl.exec_cmd("hypxrva-watcher")
end)

hl.bind("SUPER + SHIFT + G", hl.dsp.xrmonitor("gazegrab"))
hl.bind("SUPER + ALT + equal", hl.dsp.xrmonitor("gazepush 0.1"), { repeating = true })
hl.bind("SUPER + ALT + minus", hl.dsp.xrmonitor("gazepush -0.1"), { repeating = true })
hl.bind("SUPER + ALT + H", hl.dsp.xrmonitor("handinput toggle"))
hl.bind("SUPER + ALT + M", hl.dsp.xrmonitor("view toggle"),
  { description = "Toggle XR monitor view" })
hl.bind("SUPER + Home", hl.dsp.xrmonitor("center"))
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd("wivrnctl disconnect"))
