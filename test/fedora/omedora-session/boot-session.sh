#!/bin/bash
#
# Container-side launcher for the nested Omedora session.
# Runs as CMD of test/fedora/omedora-session/Dockerfile.
#
# Modes (selected via $OMEDORA_SESSION_MODE):
#
#   interactive (default)  Hyprland runs in the foreground using the wayland
#                          backend. Opens a window on the host's compositor.
#                          Inside the window you see the omedora desktop —
#                          waybar, walker on super+space, etc.
#                          Exit by closing the window or super+M (per omedora
#                          keybinds — those bind to "exit" upstream).
#
#   smoke                  Same backend as interactive, but driven by
#                          hyprctl: starts Hyprland in bg, waits for IPC
#                          ready, runs a series of assertions, exits.
#
#   headless               Hyprland uses AQ_BACKENDS=headless (no host
#                          display required). Driven by hyprctl like smoke.
#                          CI-safe. (Note: requires Hyprland to support the
#                          headless backend; older Aquamarine versions may
#                          not. If it doesn't work, fall back to Xvfb-x11
#                          via $OMEDORA_SESSION_MODE=xvfb in a follow-up.)
#
# Test/fedora/run-session.sh on the host handles the docker-run side
# (socket bind, GPU device, group propagation).

set -uo pipefail

MODE="${OMEDORA_SESSION_MODE:-interactive}"
REPO="${OMARCHY_PATH:-/home/omedora/.local/share/omarchy}"

# XDG_RUNTIME_DIR must exist and be 0700.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# Aquamarine / wlroots-style backend selection.
case "$MODE" in
  interactive|smoke)
    export AQ_BACKENDS=wayland
    export WLR_BACKENDS=wayland
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-host-wayland}"
    if [[ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
      echo "ERROR: expected host Wayland socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" >&2
      echo "       Launch via test/fedora/run-session.sh from a Wayland desktop." >&2
      exit 2
    fi
    ;;
  headless)
    export AQ_BACKENDS=headless
    export WLR_BACKENDS=headless
    unset WAYLAND_DISPLAY
    ;;
  *)
    echo "unknown OMEDORA_SESSION_MODE: $MODE (expected interactive|smoke|headless)" >&2
    exit 2
    ;;
esac

# UWSM is the upstream way to launch the Hyprland session — it sets up the
# user systemd environment and runs the right exec lines from
# hyprland.desktop. omedora's install pipeline configures it.
if command -v uwsm >/dev/null 2>&1 && [[ $MODE == "interactive" ]]; then
  echo "Launching Omedora via UWSM (nested $AQ_BACKENDS)..."
  echo "  Exit the host window to stop the session."
  exec uwsm start -- hyprland.desktop
fi

# Smoke / headless: run Hyprland directly so we can drive it via hyprctl.
echo "Launching Hyprland (mode=$MODE, backend=$AQ_BACKENDS) for hyprctl-driven smoke..."

log=$(mktemp -t hyprland-XXXXXX.log)
Hyprland >"$log" 2>&1 &
hypr_pid=$!

cleanup() {
  if kill -0 "$hypr_pid" 2>/dev/null; then
    HYPRLAND_INSTANCE_SIGNATURE="$(find_signature)" hyprctl dispatch exit >/dev/null 2>&1 || true
    sleep 0.5
    kill "$hypr_pid" 2>/dev/null || true
  fi
  echo "--- Hyprland log (tail) ---"
  tail -50 "$log" >&2 || true
}
trap cleanup EXIT

find_signature() {
  for _ in {1..50}; do
    local dir
    dir=$(find /tmp/hypr -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)
    [[ -n $dir ]] && { printf '%s' "${dir##*/}"; return 0; }
    sleep 0.1
  done
  return 1
}

echo "Waiting for Hyprland IPC..."
sig=""
for _ in {1..50}; do
  sig=$(find_signature) && break || true
  sleep 0.2
done
[[ -n $sig ]] || { echo "FAIL: Hyprland never created its IPC socket"; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE="$sig"
echo "Hyprland IPC ready (signature: $sig)"
echo ""

# Smoke assertions
if [[ -f "$REPO/test/fedora/omedora-session/smoke-assertions.sh" ]]; then
  bash "$REPO/test/fedora/omedora-session/smoke-assertions.sh"
  status=$?
else
  echo "(no smoke-assertions.sh yet; just verifying Hyprland is alive)"
  hyprctl version | head -3
  hyprctl monitors -j | jq '. | length'
  status=$?
fi

exit $status
