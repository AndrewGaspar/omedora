#!/bin/bash
#
# Shared uwsm-launch setup for the L4 session launchers (session-launch.sh =
# host-nested, session-launch-headless.sh = self-contained headless). Source
# this, then call `omedora_uwsm_prepare <host-wayland-socket>` and run
# `uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland`.
#
# Both launchers nest Omedora's Hyprland into some host Wayland compositor (the
# developer's desktop, or a container-local labwc) and want a *properly
# uwsm-managed* session — exactly what the packaged session entry
# (/usr/share/wayland-sessions/omedora.desktop) runs. `uwsm start` saves the
# launching env into the systemd user manager, activates
# graphical-session.target, and sources /usr/share/uwsm/env.d/10-omarchy (the
# omedora-settings drop-in that sets OMARCHY_PATH/TERMINAL/BROWSER/EDITOR), so
# the v4 autostart chain — `quickshell -n -p $OMARCHY_PATH/shell` plus the
# uwsm-app scopes from config/hypr/autostart.lua — comes up like a real login.
# The only difference between the two launchers is WHICH host socket Hyprland
# nests into; everything below is identical, so it lives here to keep the two
# paths from drifting apart.

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

  # OMARCHY_PATH (+ dev-link PATH adjustments) for THIS shell. The compositor
  # unit gets it again from /usr/share/uwsm/env.d/10-omarchy, but the launcher
  # itself needs it for omarchy-shell readiness checks (machinectl shell's
  # bash -c doesn't read /etc/profile.d).
  [[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] &&
    source /usr/share/omarchy/default/bash/env-bootstrap

  # GTK apps in the session (portal-gtk file pickers, …) can't use the GL
  # renderer under pure software paths; cairo always paints. Set in the session
  # env so `uwsm start` propagates it to all user scopes. Quickshell (Qt) needs
  # no equivalent — it renders fine against the passed-through render node.
  export GSK_RENDERER=cairo
  export XDG_CURRENT_DESKTOP=Hyprland

  # Satisfy uwsm's seat/VT gate: its prepare_env() only does the foreground-VT
  # lookup (which aborts with "Could not determine session on foreground VT" in
  # a container) when XDG_SEAT/XDG_SESSION_ID are empty. A fake-but-non-empty
  # XDG_SEAT + the real XDG_SESSION_ID make it skip the lookup. The XDG_SEAT
  # value is never validated against hardware once the gate is passed.
  export XDG_SEAT="${XDG_SEAT:-seat0}"
  export XDG_SESSION_ID="${XDG_SESSION_ID:-$(loginctl --no-legend list-sessions 2>/dev/null | awk 'NR==1{print $1}')}"

  omedora_install_fast_lspci_shim
}

# omedora_install_fast_lspci_shim — work around a CONTAINER-ONLY config artifact.
#
# Hyprland's Lua config has a hardware probe (default/hypr/nvidia.lua:
# `o.shell_succeeds("lspci | grep -qi nvidia")`). Under rootless podman's faked
# PCI tree, `lspci` is pathologically slow — ~2.5s of syscall time scanning PCI
# config space (verified) — which blows past Hyprland's config-reload watchdog
# and leaves a persistent on-screen banner: "Your config has errors:
# require('default.hypr.apps.system'): [Lua] execution timed out in config
# reload". (The error is attributed to whichever require was mid-flight when the
# budget blew; the real culprit is the slow lspci.) On REAL hardware lspci
# returns in milliseconds and no banner ever appears — so this is purely a
# container artifact, NOT an omedora config bug, and we must NOT patch the
# upstream nvidia.lua (rebase surface + byte-identity).
#
# Instead drop a fast `lspci` shim on the omedora user's PATH (~/.local/bin,
# ahead of /usr/bin) that reports "no PCI match" instantly, so the probe (and
# thus config load) completes well within the watchdog. Verified: reload drops
# 2.5s -> 0.16s and `hyprctl configerrors` goes empty. This touches only the
# test user's ~/.local/bin — no /etc, no system policy, no upstream config — and
# only affects nvidia.lua's no-nvidia fast path (the container has no nvidia GPU
# anyway, so reporting "none" is also correct).
omedora_install_fast_lspci_shim() {
  local shim_dir="$HOME/.local/bin"
  mkdir -p "$shim_dir"
  cat >"$shim_dir/lspci" <<'EOF'
#!/bin/sh
# L4 test scaffolding: a fast no-op lspci (the container has no real PCI to
# enumerate and the host lspci is ~2.5s slow here). Reports no devices so
# nvidia.lua's `lspci | grep -qi nvidia` returns "no nvidia" instantly.
exit 1
EOF
  chmod +x "$shim_dir/lspci"
}

# omedora_wait_for_shell <timeout-seconds>
#   Poll until the Omarchy Quickshell shell answers `omarchy-shell shell ping`
#   with "ok" — the v4 readiness signal (the bar/launcher/notifications/OSD all
#   live inside that one quickshell instance). Returns 0 when up, 1 on timeout.
omedora_wait_for_shell() {
  local timeout="${1:-60}" i
  for ((i = 0; i < timeout * 2; i++)); do
    [[ "$(omarchy-shell shell ping 2>/dev/null)" == "ok" ]] && return 0
    sleep 0.5
  done
  return 1
}
