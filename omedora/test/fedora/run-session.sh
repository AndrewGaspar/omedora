#!/bin/bash
#
# Host-side runner for the L4-nested Omedora session — systemd edition.
#
# Boots the committed session image (omedora-test:fedora44-session)
# under podman with real PID-1 systemd, waits for systemd-logind + the omedora
# user manager, then logs in as omedora via `machinectl shell` and launches the
# session.
#
# Two nesting modes:
#   (default) HOST-NESTED — Hyprland nests into the developer's *host*
#             compositor; needs a running Wayland desktop, binds the host
#             socket. Wayland-on-Wayland. One host socket => not parallelizable.
#   --headless           — the container stands up its OWN headless Wayland
#             compositor (labwc) and Hyprland nests into THAT. No host desktop,
#             no socket bind-mount, fully parallelizable + CI-able. Drive it via
#             hyprctl and screenshot with grim. See session-launch-headless.sh.
#
# Usage:
#   omedora/test/fedora/run-session.sh             # host-nested (needs a Wayland desktop)
#   omedora/test/fedora/run-session.sh --headless  # self-contained headless session
#   omedora/test/fedora/run-session.sh --rebuild   # rebuild the session image first
#   omedora/test/fedora/run-session.sh --shell     # boot, then machinectl shell (no compositor)
#   omedora/test/fedora/run-session.sh --keep      # don't remove the container on exit
#   omedora/test/fedora/run-session.sh --workstation           # run on a Fedora Workstation base
#   omedora/test/fedora/run-session.sh --workstation --gnome   # nest GNOME instead of Hyprland
#                                            #   (the GNOME fallback; implies --workstation --headless)
#
# Requirements:
#   host-nested: a running Wayland desktop on the host. podman --systemd support.
#   --headless:  podman --systemd support and a DRM render node. With a real GPU
#                pass-through is automatic (--device /dev/dri). For GPU-less CI,
#                load the host kernel `vkms` module so a software render node
#                exists, then pass OMEDORA_RENDER_NODE=/dev/dri/renderD<n>.
#
# Socket note (host-nested only): under rootless podman the container's omedora
# user maps to a subuid, so it can't connect to the host's 0755 Wayland socket.
# The runner (which owns the socket) temporarily widens it to 0777 and restores
# the original mode on exit. It's your own session socket and the window is short.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
# SESSION_IMAGE / RUN_CTR are resolved after arg parsing so --workstation can pick
# the "-workstation" image lineage + a distinct container name.
LAUNCH_DIR_IN_IMAGE=/home/omedora/.local/share/omarchy/omedora/test/fedora/omedora-session
LAUNCH_IN_IMAGE="$LAUNCH_DIR_IN_IMAGE/session-launch.sh"
LAUNCH_HEADLESS_IN_IMAGE="$LAUNCH_DIR_IN_IMAGE/session-launch-headless.sh"

rebuild=false; shell_only=false; keep=false; headless=false; workstation=false; gnome=false
for arg in "$@"; do
  case "$arg" in
    --rebuild)     rebuild=true ;;
    --shell)       shell_only=true ;;
    --keep)        keep=true ;;
    --headless)    headless=true ;;
    --workstation) workstation=true ;;
    # --gnome nests GNOME instead of Hyprland to show the GNOME fallback on the
    # Workstation base. The nested-GNOME path lives in the headless launcher and
    # needs gnome-shell (Workstation image), so it implies --workstation + --headless.
    --gnome)       gnome=true; workstation=true; headless=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# Resolve image + container names (after parsing, so --workstation applies). An
# explicit OMEDORA_SYSTEMD_SESSION_IMAGE / OMEDORA_SESSION_CTR still wins.
variant=""; $workstation && variant="-workstation"
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-omedora-test:fedora44-session${variant}}"
RUN_CTR="${OMEDORA_SESSION_CTR:-omedora-session${variant}}"

# --- preconditions -----------------------------------------------------------
if ! $headless; then
  : "${WAYLAND_DISPLAY:?need WAYLAND_DISPLAY (run from a Wayland desktop, or use --headless)}"
  : "${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR}"
  host_sock="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  [[ -S $host_sock ]] || { echo "host Wayland socket not found: $host_sock" >&2; exit 3; }
fi

# --- build the session image if needed ---------------------------------------
if $rebuild || ! podman image exists "$SESSION_IMAGE"; then
  echo "Building session image (this runs install.sh inside a systemd container)..."
  build_flags=(); $rebuild && build_flags+=(--rebuild); $workstation && build_flags+=(--workstation)
  "$REPO/omedora/test/fedora/build-session.sh" "${build_flags[@]}"
fi

# --- widen the host socket (host-nested only); clean up on exit --------------
if ! $headless; then
  orig_mode=$(stat -c '%a' "$host_sock")
fi
cleanup() {
  $headless || chmod "$orig_mode" "$host_sock" 2>/dev/null || true
  if ! $keep; then
    podman rm -f "$RUN_CTR" >/dev/null 2>&1 || true
  else
    echo "Container '$RUN_CTR' left running (--keep)."
  fi
}
trap cleanup EXIT
$headless || chmod 0777 "$host_sock"

# --- boot the container under systemd ----------------------------------------
podman rm -f "$RUN_CTR" >/dev/null 2>&1 || true
run_args=(
  -d --name "$RUN_CTR" --systemd=always
  # GPU: the render node is world-rw, so no group juggling. /dev/rfkill keeps
  # waybar's rfkill module quiet. Whole /dev/dri so Mesa can pick a device.
  --device /dev/dri
)
if ! $headless; then
  # Host compositor socket → /tmp/host-wayland (session-launch points at it).
  run_args+=(-v "$host_sock:/tmp/host-wayland")
fi
[[ -e /dev/rfkill ]] && run_args+=(--device /dev/rfkill)
# xdg-document-portal FUSE-mounts a document store at /run/user/1000/doc, which
# needs BOTH /dev/fuse AND mount(2) privilege. /dev/fuse alone is NOT enough:
# rootless podman's user-ns drops CAP_SYS_ADMIN, so fusermount3's mount fails
# with "Operation not permitted" (status 6/NOTCONFIGURED) and the unit lands in
# `failed`. --cap-add SYS_ADMIN restores the mount capability inside the user-ns
# so the portal starts cleanly (verified live: the unit goes active and
# `portal on /run/user/1000/doc type fuse.portal` appears). Bare-metal Fedora's
# user session already has this; the cap just re-grants what the rootless
# container removed. Harness-only — no /etc, no system policy (§6 forbidden
# surfaces apply to the omedora product, not the test runner).
[[ -e /dev/fuse ]] && run_args+=(--device /dev/fuse --cap-add SYS_ADMIN)

# Iterate on the launch scripts without rebuilding the image.
run_args+=(-v "$REPO/omedora/test/fedora/omedora-session/session-launch.sh:$LAUNCH_IN_IMAGE:ro")
run_args+=(-v "$REPO/omedora/test/fedora/omedora-session/session-launch-headless.sh:$LAUNCH_HEADLESS_IN_IMAGE:ro")
run_args+=(-v "$REPO/omedora/test/fedora/omedora-session/session-launch-common.sh:$LAUNCH_DIR_IN_IMAGE/session-launch-common.sh:ro")

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

if $headless; then
  echo "Launching the headless Omedora session inside the container..."
  # machinectl shell enters a real logind session (XDG_RUNTIME_DIR, user bus)
  # and runs session-launch-headless.sh, which starts labwc + nested Hyprland.
  # The script blocks until Hyprland exits (Ctrl-C to stop) unless
  # OMEDORA_HEADLESS_KEEP is set. Pass through the render-node pin if requested.
  setenv_args=()
  [[ -n "${OMEDORA_RENDER_NODE:-}" ]] && setenv_args+=(--setenv=OMEDORA_RENDER_NODE="$OMEDORA_RENDER_NODE")
  [[ -n "${OMEDORA_HEADLESS_RES:-}" ]] && setenv_args+=(--setenv=OMEDORA_HEADLESS_RES="$OMEDORA_HEADLESS_RES")
  [[ -n "${OMEDORA_HEADLESS_KEEP:-}" ]] && setenv_args+=(--setenv=OMEDORA_HEADLESS_KEEP="$OMEDORA_HEADLESS_KEEP")
  # --gnome → nest GNOME Shell instead of Hyprland (proves the GNOME fallback).
  $gnome && setenv_args+=(--setenv=OMEDORA_HEADLESS_SESSION=gnome)
  exec podman exec -it "$RUN_CTR" machinectl shell "${setenv_args[@]}" \
    omedora@.host "$LAUNCH_HEADLESS_IN_IMAGE"
fi

echo "Launching the Omedora session (close the host window to exit)..."
# -it so the compositor has a controlling terminal; machinectl shell enters a
# real logind session (XDG_RUNTIME_DIR, user bus) and runs session-launch.sh.
exec podman exec -it "$RUN_CTR" machinectl shell omedora@.host "$LAUNCH_IN_IMAGE"
