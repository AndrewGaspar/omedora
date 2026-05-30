#!/bin/bash
#
# Launch the Omedora graphical session inside the systemd container.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh), and launches the session through
# `uwsm start` — exactly as the omarchy.desktop session entry does on bare
# metal. uwsm sets up the user environment, activates graphical-session.target,
# and runs the autostart chain in proper `systemd --user` scopes. That makes
# the container session behave like a real one: PATH is propagated, env reaches
# systemd/dbus, and `uwsm-app`-launched apps (waybar, walker's gapplication
# service, ...) render correctly. Launching Hyprland directly instead led to a
# cascade of breakage (no PATH, unpropagated env, broken uwsm-app scopes).
#
# Two things make `uwsm start` work in a container:
#
#  1. The seat/VT gate. uwsm's env preloader normally calls logind to find the
#     graphical session on the foreground VT and aborts ("Could not determine
#     session on foreground VT") when there isn't one — a container has no
#     seat0/VTs. But its prepare_env() only does that lookup when XDG_SEAT or
#     XDG_SESSION_ID are empty; if both are set it skips it. `uwsm start` saves
#     the whole launching environment, so exporting a (fake but non-empty)
#     XDG_SEAT plus the real XDG_SESSION_ID below bypasses the gate. The value
#     of XDG_SEAT is never validated against hardware once the gate is passed.
#
#  2. The nesting env. uwsm deliberately strips WAYLAND_DISPLAY from the user
#     manager env (a compositor is expected to *create* its socket, not inherit
#     one). For Wayland-on-Wayland nesting we instead feed it — plus the
#     aquamarine/wlroots backend selection — to the compositor unit via a
#     drop-in. (Container-test-only: it hardcodes the bind-mounted host socket.)

set -uo pipefail

# Host compositor socket (bind-mounted by the runner at /tmp/host-wayland).
if [[ ! -S /tmp/host-wayland ]]; then
  echo "ERROR: host Wayland socket not present at /tmp/host-wayland" >&2
  echo "       Run via test/fedora/run-session.sh from a Wayland desktop." >&2
  exit 2
fi

# (2) Feed the nesting env to the compositor service (uwsm strips WAYLAND_DISPLAY
# from the user-manager env, so a drop-in is the way to get it to the unit).
mkdir -p "$HOME/.config/systemd/user/wayland-wm@.service.d"
cat >"$HOME/.config/systemd/user/wayland-wm@.service.d/10-nest.conf" <<'EOF'
[Service]
Environment=WAYLAND_DISPLAY=/tmp/host-wayland
Environment=AQ_BACKENDS=wayland
Environment=WLR_BACKENDS=wayland
EOF
systemctl --user daemon-reload 2>/dev/null || true

# omarchy's session environment (PATH with the omarchy bin dir, TERMINAL,
# BROWSER, EDITOR, mise). `uwsm start` saves the launching env and propagates
# it, so sourcing this here is what gets omarchy-* onto the user manager's PATH.
[[ -f "$HOME/.config/uwsm/env" ]] && source "$HOME/.config/uwsm/env"

# The container has no GPU (software rendering), so force GTK4 apps to the cairo
# renderer — the default GL/Vulkan renderer fails to paint here. Set it in the
# session env so it propagates (via uwsm) to ALL user scopes, including the
# walker autostart service. (omarchy-launch-walker sets cairo for its own
# walker, but the autostart unit doesn't, which left it unable to render the
# menu.) Test-only: real hardware wants the GL renderer.
export GSK_RENDERER=cairo

# (1) Satisfy uwsm's seat/VT gate so the env preloader skips the foreground-VT
# lookup that fails in a container.
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SEAT="${XDG_SEAT:-seat0}"
export XDG_SESSION_ID="${XDG_SESSION_ID:-$(loginctl --no-legend list-sessions 2>/dev/null | awk 'NR==1{print $1}')}"

echo "Starting Omedora via uwsm (nested wayland; session=${XDG_SESSION_ID:-?}, seat=$XDG_SEAT)"
echo "  Close the host window to end the session."

# uwsm activates graphical-session.target, which brings up the WantedBy= user
# services (elephant, pipewire, wireplumber, ...) and runs autostart in proper
# scopes — no manual `systemctl --user start` workarounds needed anymore.
exec uwsm start -- hyprland.desktop
