#!/bin/bash
#
# Launch the Omedora graphical session inside the systemd container, nesting
# Hyprland into the developer's HOST Wayland compositor (the socket the runner
# bind-mounted at /tmp/host-wayland). For the self-contained headless variant
# see session-launch-headless.sh; the shared uwsm-launch setup both use is in
# session-launch-common.sh.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh) and launches the session through
# `uwsm start` — exactly as the omarchy.desktop session entry does on bare
# metal. uwsm sets up the user environment, activates graphical-session.target,
# and runs the autostart chain in proper `systemd --user` scopes, so the
# container session behaves like a real one (PATH propagated, env in
# systemd/dbus, uwsm-app apps render). See session-launch-common.sh for how
# `uwsm start` is made to work in a container (seat/VT gate + the nesting env).

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

# Drive Hyprland directly via uwsm (no resolver .desktop) — matches
# default/wayland-sessions/omedora.desktop. We run `start-hyprland` (the upstream
# watchdog launcher that supervises Hyprland and passes --watchdog-fd; running
# the bare `Hyprland` binary triggers its "started without start-hyprland"
# warning). -N/-D supply the session metadata a .desktop would otherwise provide;
# the uwsm unit instance becomes wayland-wm@start\x2dhyprland.service.
exec uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland
