#!/bin/bash
#
# Launch the Omedora graphical session inside the systemd container.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh). Because it's a real session,
# XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS, and the `systemd --user` manager
# are already set up by pam_systemd — exactly like a bare-metal TTY/DM login.
#
# The only thing this adds over a bare-metal launch is the Wayland-on-Wayland
# nesting: Hyprland's `wayland` backend makes it a Wayland *client* of the
# host compositor (whose socket the runner bind-mounted at /tmp/host-wayland)
# instead of driving DRM/KMS directly.
#
# Why not `uwsm start`? Upstream's omarchy.desktop launches via
# `uwsm start -g -1 -e -D Hyprland hyprland.desktop`, but uwsm's environment
# preloader is seat/VT-aware: it calls loginctl to find the session attached to
# the foreground VT and aborts ("Could not determine session on foreground VT")
# when there isn't one. A container has no seat0 and no VTs, so `uwsm start`
# can't run there — it's the wrong tool for a nested session.
#
# Launching Hyprland directly under this real logind + `systemd --user` session
# is faithful in every way that matters for L4: the autostart chain in
# default/hypr/autostart.lua wraps each app in `uwsm-app -- <cmd>`, and the real
# `uwsm-app` hands those off to the running user systemd manager — so waybar,
# mako, swaybg, hypridle, fcitx5 et al. start exactly as on bare metal. (Proven:
# 0/13 autostart entries fired under the old no-systemd image; all fire here.)

set -uo pipefail

# Host compositor socket (bind-mounted by the runner). An absolute WAYLAND_DISPLAY
# is used verbatim by libwayland, so the nesting backend connects to the host.
export WAYLAND_DISPLAY=/tmp/host-wayland
if [[ ! -S $WAYLAND_DISPLAY ]]; then
  echo "ERROR: host Wayland socket not present at $WAYLAND_DISPLAY" >&2
  echo "       Run via test/fedora/run-session.sh from a Wayland desktop." >&2
  exit 2
fi

# omarchy's session environment — PATH (so omarchy-* bins resolve), TERMINAL,
# BROWSER, EDITOR, mise — lives in ~/.config/uwsm/env, normally sourced by
# `uwsm start`. We launch Hyprland directly, so source it ourselves. Without
# this the omarchy bin dir isn't on PATH, and every keybind that calls
# omarchy-menu / omarchy-launch-walker (Super+Space, the menus, theme switch,
# screenshots, ...) silently fails with "command not found".
[[ -f "$HOME/.config/uwsm/env" ]] && source "$HOME/.config/uwsm/env"

# Nest under the host compositor instead of DRM/KMS.
export AQ_BACKENDS=wayland
export WLR_BACKENDS=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland

echo "Starting Omedora (nested wayland; session=${XDG_SESSION_ID:-?}, runtime=$XDG_RUNTIME_DIR)"
echo "  Close the host window to end the session."

# Several user services are WantedBy graphical-session.target, which our direct
# Hyprland launch (no uwsm) doesn't activate. Start them explicitly:
#   - elephant: walker's data-provider backend (else Super+Space has no results)
#   - pipewire / pipewire-pulse / wireplumber: the audio stack waybar's volume
#     module talks to (else the audio icon is blank until first interaction)
# All harmless if absent.
systemctl --user start elephant.service 2>/dev/null || true
systemctl --user start pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || true

exec Hyprland
