#!/bin/bash
#
# Launch the Omedora graphical session FULLY HEADLESS inside the systemd
# container — no host Wayland desktop, no host socket bind-mount.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh --headless). Like its sibling
# session-launch.sh it relies on pam_systemd having set up XDG_RUNTIME_DIR,
# the user D-Bus and the `systemd --user` manager.
#
# The difference from session-launch.sh: instead of nesting Hyprland into the
# *host's* compositor, we stand up our OWN headless Wayland compositor (labwc,
# wlroots headless backend) inside the container and nest Omedora's Hyprland
# into THAT. This is what makes the L4 test parallelizable and CI-able: every
# container is self-contained, with no shared host state.
#
# Why labwc as the nesting host (and not weston/sway/cage)?
#   Hyprland 0.55.2 uses Aquamarine 0.12, whose nested ("wayland") backend
#   HARD-REQUIRES the host compositor to advertise BOTH:
#     - xdg_wm_base version 6   (weston 15 and sway 1.11 only expose v5 ->
#                                "invalid version for global xdg_wm_base")
#     - zwp_linux_dmabuf_v1     (weston's headless backend never exports it,
#                                regardless of renderer -> "Missing protocols")
#   labwc 0.9.6 (wlroots 0.19) exposes xdg_wm_base v6 AND linux-dmabuf when it
#   runs its GLES2 renderer over a DRM render node. It's the lightest headless
#   compositor in Fedora 44 that satisfies both. See omedora/testing.md.
#
# GPU / software-rendering note:
#   Aquamarine's GBM allocator needs a DRM *render node* (/dev/dri/renderD*).
#   With a real GPU, pass --device /dev/dri (the runner does). For GPU-less CI,
#   load the kernel `vkms` module on the host and pass that render node — it
#   gives a software DRM device that llvmpipe renders into. A pure-pixman path
#   (no render node at all) does NOT work: aquamarine has no shm fallback for
#   nesting.
#
# Env knobs (all optional):
#   OMEDORA_HEADLESS_RES   default 1920x1080 — nested monitor resolution
#   OMEDORA_RENDER_NODE    pin labwc + aquamarine to a specific render node
#                          (e.g. /dev/dri/renderD129). Needed on multi-GPU hosts
#                          where one node's GBM allocator fails (e.g. NVIDIA).
#                          If unset, labwc/wlroots auto-pick a node.
#   OMEDORA_HEADLESS_KEEP  if set, this script exits 0 after the session is up
#                          and leaves it running (for scripted/CI driving).
#                          Otherwise it blocks until Hyprland exits.

set -uo pipefail

RES="${OMEDORA_HEADLESS_RES:-1920x1080}"

log() { printf '[headless] %s\n' "$*"; }

# --- 0. sanity --------------------------------------------------------------
: "${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR (run via machinectl shell)}"
command -v labwc    >/dev/null || { echo "labwc not installed (add to Dockerfile.base)" >&2; exit 2; }
command -v Hyprland >/dev/null || { echo "Hyprland not installed" >&2; exit 2; }

# Pick / honor a render node. Aquamarine's GBM allocator must use one that
# actually allocates (NVIDIA render nodes can fail "Couldn't allocate a gbm
# buffer"); AMD/Intel/llvmpipe-vkms work. Caller can pin via OMEDORA_RENDER_NODE.
NODE="${OMEDORA_RENDER_NODE:-}"
labwc_node_env=()
if [[ -n $NODE ]]; then
  [[ -e $NODE ]] || { echo "OMEDORA_RENDER_NODE=$NODE does not exist" >&2; exit 2; }
  labwc_node_env=(--setenv=WLR_RENDER_DRM_DEVICE="$NODE")
  log "pinning render node: $NODE"
fi

# Source omarchy's session env (PATH for omarchy-* bins, TERMINAL, etc.) — the
# autostart chain and keybinds need it. Same rationale as session-launch.sh.
[[ -f "$HOME/.config/uwsm/env" ]] && source "$HOME/.config/uwsm/env"

# --- 1. start the headless host compositor (labwc) --------------------------
# Run as a transient user unit so it survives this shell and is easy to stop.
# labwc ships with cap_sys_nice (file capability); under rootless podman that
# cap isn't in the user-ns bounding set, so systemd's exec would fail 203 with
# the cap set. The Dockerfile strips it (setcap -r) at build time.
log "starting labwc (wlroots headless backend)"
systemctl --user reset-failed omedora-labwc 2>/dev/null || true
systemd-run --user --quiet --unit=omedora-labwc \
  --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  --setenv=WLR_BACKENDS=headless \
  --setenv=WLR_LIBINPUT_NO_DEVICES=1 \
  --setenv=WLR_RENDERER_ALLOW_SOFTWARE=1 \
  "${labwc_node_env[@]}" \
  labwc

# Wait for labwc's wayland socket to appear.
HOST_WL=""
for _ in $(seq 1 30); do
  HOST_WL=$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
  [[ -n $HOST_WL ]] && break
  [[ "$(systemctl --user is-active omedora-labwc)" == "failed" ]] && {
    echo "labwc failed to start:" >&2
    journalctl --user -u omedora-labwc --no-pager | tail -20 >&2
    exit 1
  }
  sleep 0.5
done
[[ -n $HOST_WL ]] || { echo "labwc never created a wayland socket" >&2; exit 1; }
log "labwc up on host socket: $HOST_WL"

# --- 2. nest Omedora's Hyprland into labwc ----------------------------------
log "starting nested Hyprland (Aquamarine wayland backend -> $HOST_WL)"
systemctl --user reset-failed omedora-hypr 2>/dev/null || true
hypr_env=(
  --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"
  --setenv=WAYLAND_DISPLAY="$HOST_WL"
  --setenv=XDG_CURRENT_DESKTOP=Hyprland
  --setenv=XDG_SESSION_TYPE=wayland
)
[[ -n $NODE ]] && hypr_env+=(--setenv=AQ_DRM_DEVICES="$NODE")

systemd-run --user --quiet --unit=omedora-hypr "${hypr_env[@]}" Hyprland

# Wait for Hyprland's IPC socket.
SIG=""
for _ in $(seq 1 30); do
  SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
  [[ -n $SIG && -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]] && break
  [[ "$(systemctl --user is-active omedora-hypr)" == "failed" ]] && {
    echo "Hyprland failed to start:" >&2
    journalctl --user -u omedora-hypr --no-pager | tail -20 >&2
    exit 1
  }
  sleep 0.5
done
[[ -n $SIG ]] || { echo "Hyprland never created its IPC socket" >&2; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
log "Hyprland IPC up (instance $SIG)"

# --- 3. ensure a usable monitor --------------------------------------------
# The nested aquamarine WAYLAND-1 output does not always promote to a Hyprland
# monitor on its own under this lionheartp v0.55.2 build, so create an explicit
# headless output. (hyprctl `keyword` is rejected by the Lua config parser, but
# `output create headless` works.)
sleep 1
hyprctl output create headless >/dev/null 2>&1 || true
for _ in $(seq 1 10); do
  n=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  [[ "$n" -ge 1 ]] && break
  sleep 0.5
done

read -r MON MW MH < <(hyprctl monitors -j 2>/dev/null | python3 -c \
  'import sys,json;d=json.load(sys.stdin);print(d[0]["name"],d[0]["width"],d[0]["height"]) if d else print("","0","0")' 2>/dev/null)
log "monitor: ${MON:-<none>} ${MW}x${MH}"

# Hyprland's own wayland socket — clients (grim, foot, screenshots) talk to it.
HYPR_WL=$(hyprctl instances -j 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["wl_socket"])' 2>/dev/null)

cat <<EOF

================ Omedora headless session is up ================
  labwc (host):      WAYLAND_DISPLAY=$HOST_WL
  Hyprland (nested): WAYLAND_DISPLAY=$HYPR_WL   monitor=$MON
  IPC:               HYPRLAND_INSTANCE_SIGNATURE=$SIG

  Drive it (inside the container, as omedora):
    export HYPRLAND_INSTANCE_SIGNATURE=$SIG
    export WAYLAND_DISPLAY=$HYPR_WL
    hyprctl monitors
    grim /tmp/shot.png            # capture the whole output
    foot                          # open a terminal into the session

  Stop it:
    systemctl --user stop omedora-hypr omedora-labwc
================================================================
EOF

# --- 4. block (or return for scripted driving) ------------------------------
if [[ -n "${OMEDORA_HEADLESS_KEEP:-}" ]]; then
  log "session left running (OMEDORA_HEADLESS_KEEP set); returning."
  exit 0
fi

log "blocking until Hyprland exits (Ctrl-C to stop)..."
# Follow the unit; when Hyprland goes away this returns.
while [[ "$(systemctl --user is-active omedora-hypr 2>/dev/null)" == "active" ]]; do
  sleep 2
done
log "Hyprland exited."
