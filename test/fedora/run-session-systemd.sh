#!/bin/bash
#
# Host-side runner for the L4-nested Omedora session — systemd edition.
#
# Boots the committed session image (omedora-test:fedora44-session-systemd)
# under podman with real PID-1 systemd, waits for systemd-logind + the omedora
# user manager, then logs in as omedora via `machinectl shell` and launches the
# session with `uwsm` — the same path a bare-metal Fedora user hits. Hyprland
# nests under the host compositor (Wayland-on-Wayland).
#
# Usage:
#   test/fedora/run-session-systemd.sh            # build if needed, boot, launch session
#   test/fedora/run-session-systemd.sh --rebuild  # rebuild the session image first
#   test/fedora/run-session-systemd.sh --shell    # boot, then machinectl shell (no compositor)
#   test/fedora/run-session-systemd.sh --keep      # don't remove the container on exit
#
# Requirements: a running Wayland desktop on the host (provides the socket the
# nested Hyprland renders into). podman with --systemd support.
#
# Socket note: under rootless podman the container's omedora user maps to a
# subuid, so it can't connect to the host's 0755 Wayland socket. The runner
# (which owns the socket) temporarily widens it to 0777 and restores the
# original mode on exit. It's your own session socket and the window is short.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-omedora-test:fedora44-session-systemd}"
RUN_CTR="${OMEDORA_SESSION_CTR:-omedora-session}"
LAUNCH_IN_IMAGE=/home/omedora/.local/share/omarchy/test/fedora/omedora-session-systemd/session-launch.sh

rebuild=false; shell_only=false; keep=false
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild=true ;;
    --shell)   shell_only=true ;;
    --keep)    keep=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# --- preconditions -----------------------------------------------------------
: "${WAYLAND_DISPLAY:?need WAYLAND_DISPLAY (run from a Wayland desktop)}"
: "${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR}"
host_sock="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
[[ -S $host_sock ]] || { echo "host Wayland socket not found: $host_sock" >&2; exit 3; }

# --- build the session image if needed ---------------------------------------
if $rebuild || ! podman image exists "$SESSION_IMAGE"; then
  echo "Building session image (this runs install.sh inside a systemd container)..."
  rebuild_flag=(); $rebuild && rebuild_flag=(--rebuild)
  "$REPO/test/fedora/build-session-systemd.sh" "${rebuild_flag[@]}"
fi

# --- widen the host socket; restore + clean up on exit -----------------------
orig_mode=$(stat -c '%a' "$host_sock")
cleanup() {
  chmod "$orig_mode" "$host_sock" 2>/dev/null || true
  if ! $keep; then
    podman rm -f "$RUN_CTR" >/dev/null 2>&1 || true
  else
    echo "Container '$RUN_CTR' left running (--keep)."
  fi
}
trap cleanup EXIT
chmod 0777 "$host_sock"

# --- boot the container under systemd ----------------------------------------
podman rm -f "$RUN_CTR" >/dev/null 2>&1 || true
run_args=(
  -d --name "$RUN_CTR" --systemd=always
  # Host compositor socket → /tmp/host-wayland (session-launch points at it).
  -v "$host_sock:/tmp/host-wayland"
  # GPU: the render node is world-rw, so no group juggling. /dev/rfkill keeps
  # waybar's rfkill module quiet. Whole /dev/dri so Mesa can pick a device.
  --device /dev/dri
)
[[ -e /dev/rfkill ]] && run_args+=(--device /dev/rfkill)

# Iterate on session-launch.sh without rebuilding the image.
run_args+=(-v "$REPO/test/fedora/omedora-session-systemd/session-launch.sh:$LAUNCH_IN_IMAGE:ro")

echo "Booting $SESSION_IMAGE under systemd..."
podman run "${run_args[@]}" "$SESSION_IMAGE" >/dev/null

echo "Waiting for systemd + omedora user manager..."
for i in $(seq 1 60); do
  state=$(podman exec "$RUN_CTR" systemctl is-system-running 2>/dev/null || true)
  case "$state" in running|degraded) break ;; esac
  [[ $i -eq 60 ]] && { echo "systemd never settled (last: ${state:-none})"; podman logs "$RUN_CTR" | tail -20; exit 1; }
  sleep 1
done
for i in $(seq 1 30); do
  [[ "$(podman exec "$RUN_CTR" systemctl is-active user@1000.service 2>/dev/null || true)" == "active" ]] && break
  [[ $i -eq 30 ]] && { echo "user@1000.service never active"; exit 1; }
  sleep 1
done
echo "  systemd: $state, user@1000: active"

# --- launch ------------------------------------------------------------------
if $shell_only; then
  echo "Dropping into a logind shell as omedora (no compositor)."
  exec podman exec -it "$RUN_CTR" machinectl shell omedora@.host
fi

echo "Launching the Omedora session (close the host window to exit)..."
# -it so the compositor has a controlling terminal; machinectl shell enters a
# real logind session (XDG_RUNTIME_DIR, user bus) and runs session-launch.sh.
exec podman exec -it "$RUN_CTR" machinectl shell omedora@.host "$LAUNCH_IN_IMAGE"
