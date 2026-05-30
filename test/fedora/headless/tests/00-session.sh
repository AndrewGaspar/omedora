#!/bin/bash
#
# L4-headless smoke test: the nested Omedora session is alive.
#
# Asserts Hyprland IPC is up, there is at least one monitor, and the core
# autostart chain (waybar, mako, swaybg) is running. This is the first test the
# orchestrator runs; if it fails, later tests are meaningless.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

# Hyprland IPC reachable (a version string proves the socket answers).
ver=$(hyprctl version 2>/dev/null || true)
assert_output_contains "Hyprland IPC responds" "$ver" "Hyprland"

# A usable monitor exists (the headless output the launcher created).
assert_monitor "session has a monitor"

# Core autostart processes are up. These start via uwsm app scopes; pgrep -f is
# enough to confirm the autostart chain came up under the session.
assert_proc waybar "waybar autostart running"
assert_proc mako   "mako autostart running"
assert_proc swaybg "swaybg autostart running"
