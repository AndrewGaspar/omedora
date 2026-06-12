#!/bin/bash
#
# Launch the Omedora v4 graphical session inside the systemd container, nesting
# Hyprland into the developer's HOST Wayland compositor (the socket the runner
# bind-mounted at /tmp/host-wayland). For the self-contained headless variant
# see session-launch-headless.sh; the shared uwsm-launch setup both use is in
# session-launch-common.sh.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh) and launches the session through
# `uwsm start` — exactly as the packaged omedora.desktop session entry does on
# bare metal. uwsm sets up the user environment (incl. OMARCHY_PATH via
# /usr/share/uwsm/env.d/10-omarchy), activates graphical-session.target, and
# Hyprland boots the Lua config (~/.config/hypr/hyprland.lua), whose autostart
# (config/hypr/autostart.lua + default/hypr/autostart.lua) starts the
# Quickshell shell (`quickshell -n -p $OMARCHY_PATH/shell`) — the v4 desktop:
# bar, launcher, notifications, OSD all live in that one process. See
# session-launch-common.sh for how `uwsm start` is made to work in a container
# (seat/VT gate + the nesting env).

set -uo pipefail

# Host compositor socket (bind-mounted by the runner at /tmp/host-wayland).
if [[ ! -S /tmp/host-wayland ]]; then
  echo "ERROR: host Wayland socket not present at /tmp/host-wayland" >&2
  echo "       Run via omedora/test/fedora/run-session.sh from a Wayland desktop." >&2
  exit 2
fi

source "$(dirname -- "${BASH_SOURCE[0]}")/session-launch-common.sh"
omedora_uwsm_prepare /tmp/host-wayland

echo "Starting Omedora via uwsm (nested into host compositor; session=${XDG_SESSION_ID:-?})"
echo "  Close the host window to end the session."

# Drive Hyprland directly via uwsm (no resolver .desktop) — matches the
# packaged /usr/share/wayland-sessions/omedora.desktop. We run `start-hyprland`
# (the upstream watchdog launcher that supervises Hyprland and passes
# --watchdog-fd; running the bare `Hyprland` binary triggers its "started
# without start-hyprland" warning). -N/-D supply the session metadata a
# .desktop would otherwise provide; the uwsm unit instance becomes
# wayland-wm@start\x2dhyprland.service.
exec uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland
