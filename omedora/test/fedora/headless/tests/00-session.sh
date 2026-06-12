#!/bin/bash
#
# L4-headless smoke test: the nested Omedora v4 session is alive.
#
# Asserts Hyprland IPC is up, there is at least one monitor, the Quickshell
# shell process is running AND answers IPC (`omarchy-shell shell ping` → ok),
# and the bar actually mapped a layer surface (`omarchy-bar` in hyprctl
# layers). This is the first test the orchestrator runs; if it fails, later
# tests are meaningless.
#
# v4 note: the 3.8.2-era autostart trio (waybar/mako/swaybg) is gone — the
# bar, notifications, OSD, launcher and wallpaper all live inside ONE
# quickshell process started by the Hyprland Lua autostart
# (`quickshell -n -p $OMARCHY_PATH/shell`, default/hypr/autostart.lua).
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

# Hyprland IPC reachable (a version string proves the socket answers).
ver=$(hyprctl version 2>/dev/null || true)
assert_output_contains "Hyprland IPC responds" "$ver" "Hyprland"

# A usable monitor exists (the headless output the launcher created).
assert_monitor "session has a monitor"

# The Quickshell shell process came up from the Lua autostart.
assert_proc quickshell "quickshell process running (the v4 shell host)"

# ...and it answers IPC — the canonical v4 readiness signal.
wait_for_shell_ping 30 || true
assert_shell_ping "omarchy-shell shell ping answers ok"

# The bar is not merely alive but MAPPED: its layer surface is registered with
# the compositor. (A wedged QML bar would pass the proc/ping checks but never
# create this layer.)
wait_for_layer omarchy-bar 15 || true
assert_layer omarchy-bar "shell bar layer present (omarchy-bar)"

# The wallpaper service mapped its background layer too.
wait_for_layer omarchy-background 15 || true
assert_layer omarchy-background "shell background layer present (omarchy-background)"
