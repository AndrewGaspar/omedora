#!/bin/bash
#
# Shared uwsm-launch setup for the L4 session launchers (session-launch.sh =
# host-nested, session-launch-headless.sh = self-contained headless). Source
# this, then call `omedora_uwsm_prepare <host-wayland-socket>` and run
# `uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland`.
#
# Both launchers nest Omedora's Hyprland into some host Wayland compositor (the
# developer's desktop, or a container-local labwc) and want a *properly
# uwsm-managed* session — that's what gets PATH propagated to the systemd user
# manager, env into systemd/dbus, and autostart/keybind apps into real
# `systemd --user` scopes (so omarchy-* resolve and uwsm-app-launched apps like
# the walker service render). The only difference between the two launchers is
# WHICH host socket Hyprland nests into; everything below is identical, so it
# lives here to keep the two paths from drifting apart.

# omedora_uwsm_prepare <host-wayland-socket>
#   Configure the environment + a compositor drop-in so `uwsm start` works in a
#   container nesting into <host-wayland-socket>, then leave the caller to run
#   `uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland`.
omedora_uwsm_prepare() {
  local host_wl="$1"

  # uwsm deliberately strips WAYLAND_DISPLAY from the user-manager env (a
  # compositor is expected to CREATE its socket, not inherit one). For nesting
  # we must feed it — plus the backend selection — to the compositor unit via a
  # drop-in. host_wl is the socket Hyprland's aquamarine backend connects to.
  mkdir -p "$HOME/.config/systemd/user/wayland-wm@.service.d"
  cat >"$HOME/.config/systemd/user/wayland-wm@.service.d/10-nest.conf" <<EOF
[Service]
Environment=WAYLAND_DISPLAY=$host_wl
Environment=AQ_BACKENDS=wayland
Environment=WLR_BACKENDS=wayland
EOF
  systemctl --user daemon-reload 2>/dev/null || true

  # omarchy's session env (PATH with the omarchy bin dir, TERMINAL, BROWSER,
  # EDITOR, mise). `uwsm start` saves the launching env and propagates it, so
  # sourcing this is what gets omarchy-* onto the user manager's PATH.
  [[ -f "$HOME/.config/uwsm/env" ]] && source "$HOME/.config/uwsm/env"

  # The container renders in software, so force GTK4 to the cairo renderer (its
  # default GL/Vulkan renderer can't paint here). Set in the session env so it
  # propagates to all user scopes (waybar, the walker service, ...).
  export GSK_RENDERER=cairo
  export XDG_CURRENT_DESKTOP=Hyprland

  # Satisfy uwsm's seat/VT gate: its prepare_env() only does the foreground-VT
  # lookup (which aborts with "Could not determine session on foreground VT" in
  # a container) when XDG_SEAT/XDG_SESSION_ID are empty. A fake-but-non-empty
  # XDG_SEAT + the real XDG_SESSION_ID make it skip the lookup. The XDG_SEAT
  # value is never validated against hardware once the gate is passed.
  export XDG_SEAT="${XDG_SEAT:-seat0}"
  export XDG_SESSION_ID="${XDG_SESSION_ID:-$(loginctl --no-legend list-sessions 2>/dev/null | awk 'NR==1{print $1}')}"
}
