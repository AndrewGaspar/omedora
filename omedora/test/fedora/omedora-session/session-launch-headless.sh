#!/bin/bash
#
# Launch the Omedora graphical session FULLY HEADLESS inside the systemd
# container — no host Wayland desktop, no host socket bind-mount.
#
# Runs AS the omedora user INSIDE a real logind session (entered via
# `machinectl shell` by run-session.sh --headless). Unlike session-launch.sh
# (which nests into the developer's host compositor), this stands up its OWN
# headless Wayland compositor (labwc) inside the container and nests Omedora's
# Hyprland into THAT via `uwsm start`. That's what makes the L4 test
# parallelizable and CI-able: every container is self-contained.
#
# The Hyprland launch itself is identical to the host-nested path — same
# `uwsm start` setup from session-launch-common.sh — so the two can't drift.
# The only difference is the nesting target (labwc's socket vs the host's).
#
# Why labwc as the nesting host (and not weston/sway/cage)?
#   Hyprland 0.55.2 uses Aquamarine 0.12, whose nested ("wayland") backend
#   HARD-REQUIRES the host compositor to advertise BOTH:
#     - xdg_wm_base version 6   (weston 15 and sway 1.11 only expose v5 ->
#                                "invalid version for global xdg_wm_base")
#     - zwp_linux_dmabuf_v1     (weston's headless backend never exports it ->
#                                "Missing protocols")
#   labwc 0.9.6 (wlroots 0.19) exposes both over a DRM render node. See
#   omedora/testing.md.
#
# GPU / software-rendering note:
#   Aquamarine's GBM allocator needs a DRM *render node* (/dev/dri/renderD*).
#   With a real GPU, pass --device /dev/dri (the runner does). For GPU-less CI,
#   load the kernel `vkms` module on the host and pass that render node — it
#   gives a software DRM device. A pure-pixman path (no render node) does NOT
#   work: aquamarine has no shm fallback for nesting.
#
# Env knobs (all optional):
#   OMEDORA_HEADLESS_RES   default 1920x1080 — nested monitor resolution
#   OMEDORA_RENDER_NODE    pin labwc + aquamarine to a render node (e.g.
#                          /dev/dri/renderD129) on multi-GPU hosts where one
#                          node's GBM allocator fails (e.g. NVIDIA).
#   OMEDORA_HEADLESS_KEEP  if set, exit 0 once the session is up, leaving it
#                          running (for scripted/CI driving). Otherwise block
#                          until the session ends.
#   OMEDORA_HEADLESS_SESSION  which session to nest into labwc:
#                          'hyprland' (default) = Omedora's Hyprland via uwsm;
#                          'gnome' = nest GNOME Shell (Mutter --nested) instead,
#                          to interactively prove GNOME is a selectable fallback
#                          on the --workstation base. 'gnome' needs the Workstation
#                          image (gnome-shell present); see run-session.sh --gnome.

set -uo pipefail

RES="${OMEDORA_HEADLESS_RES:-1920x1080}"
SESSION="${OMEDORA_HEADLESS_SESSION:-hyprland}"
log() { printf '[headless] %s\n' "$*"; }

# --- 0. sanity --------------------------------------------------------------
: "${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR (run via machinectl shell)}"
command -v labwc    >/dev/null || { echo "labwc not installed (add to Dockerfile.base)" >&2; exit 2; }
if [[ "$SESSION" != "gnome" ]]; then
  command -v Hyprland >/dev/null || { echo "Hyprland not installed" >&2; exit 2; }
  command -v uwsm     >/dev/null || { echo "uwsm not installed" >&2; exit 2; }
fi

# Pick / honor a render node for labwc (and aquamarine, below).
NODE="${OMEDORA_RENDER_NODE:-}"
labwc_node_env=()
if [[ -n $NODE ]]; then
  [[ -e $NODE ]] || { echo "OMEDORA_RENDER_NODE=$NODE does not exist" >&2; exit 2; }
  labwc_node_env=(--setenv=WLR_RENDER_DRM_DEVICE="$NODE")
  log "pinning render node: $NODE"
fi

# --- 1. start the headless host compositor (labwc) --------------------------
# Transient user unit so it survives this shell. labwc ships with cap_sys_nice
# (file capability) which isn't in rootless podman's user-ns bounding set, so
# systemd's exec would fail 203 with the cap set — the Dockerfile strips it.
log "starting labwc (wlroots headless backend)"
systemctl --user reset-failed omedora-labwc 2>/dev/null || true
systemd-run --user --quiet --unit=omedora-labwc \
  --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  --setenv=WLR_BACKENDS=headless \
  --setenv=WLR_LIBINPUT_NO_DEVICES=1 \
  --setenv=WLR_RENDERER_ALLOW_SOFTWARE=1 \
  "${labwc_node_env[@]}" \
  labwc

# Wait for labwc's wayland socket (this is the socket Hyprland nests into).
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

# --- 2g. GNOME session branch (interactive coexistence check) ----------------
# When asked for GNOME (run-session.sh --workstation --gnome), nest GNOME Shell
# into labwc INSTEAD of Hyprland. This proves GNOME is a live, selectable session
# on the Workstation base — the real GDM greeter can't run in rootless nested
# podman (no seat/DRM master), so this is the container-friendly stand-in for
# "log out of Hyprland, log into GNOME". Best-effort + interactive: GNOME Shell
# under software rendering (llvmpipe) is heavy and is NOT golden-imaged.
if [[ "$SESSION" == "gnome" ]]; then
  command -v gnome-shell >/dev/null || {
    echo "gnome-shell not installed — this needs the --workstation image" >&2; exit 2; }
  log "starting nested GNOME Shell (Mutter --nested) -> $HOST_WL"
  systemctl --user reset-failed omedora-gnome 2>/dev/null || true
  # Mutter's nested mode runs GNOME Shell as a Wayland client of labwc. It needs
  # its own session bus (dbus-run-session) for gnome-shell's many bus services.
  systemd-run --user --quiet --unit=omedora-gnome \
    --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    --setenv=WAYLAND_DISPLAY="$HOST_WL" \
    --setenv=GDK_BACKEND=wayland \
    --setenv=XDG_CURRENT_DESKTOP=GNOME \
    --setenv=XDG_SESSION_TYPE=wayland \
    --setenv=MUTTER_DEBUG_DUMMY_MODE_SPECS="$RES" \
    dbus-run-session -- gnome-shell --nested --wayland

  # Confirm Mutter came up (a nested GNOME opens a SECOND wayland socket) and
  # didn't immediately crash.
  up=false
  for _ in $(seq 1 30); do
    [[ "$(systemctl --user is-active omedora-gnome 2>/dev/null)" == "failed" ]] && {
      echo "GNOME Shell failed to start:" >&2
      journalctl --user -u omedora-gnome --no-pager | tail -30 >&2
      exit 1
    }
    socks=$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -cE '^wayland-[0-9]+$')
    [[ "${socks:-0}" -ge 2 ]] && { up=true; break; }
    sleep 0.5
  done
  $up && log "nested GNOME Shell is up" || log "GNOME Shell unit active but no nested socket yet (continuing)"

  cat <<EOF

================ GNOME (nested) session is up ==================
  labwc (host):   WAYLAND_DISPLAY=$HOST_WL
  GNOME Shell:    systemd --user unit 'omedora-gnome' (Mutter --nested)
  This proves GNOME is a selectable fallback alongside Omedora/Hyprland on
  the Workstation base. The real GDM greeter/session-picker is an L4-VM thing.

  Stop it:
    systemctl --user stop omedora-gnome omedora-labwc
================================================================
EOF

  if [[ -n "${OMEDORA_HEADLESS_KEEP:-}" ]]; then
    log "GNOME session left running (OMEDORA_HEADLESS_KEEP set); returning."
    exit 0
  fi
  log "blocking until the GNOME session ends (Ctrl-C to stop)..."
  while [[ "$(systemctl --user is-active omedora-gnome 2>/dev/null)" == "active" ]]; do
    sleep 2
  done
  log "GNOME session ended."
  exit 0
fi

# --- 2. nest Omedora's Hyprland into labwc via uwsm start --------------------
# Same uwsm launch the host-nested path uses (PATH propagation, proper scopes),
# just pointed at labwc's socket instead of /tmp/host-wayland.
source "$(dirname -- "${BASH_SOURCE[0]}")/session-launch-common.sh"
omedora_uwsm_prepare "$HOST_WL"

# Pin aquamarine to the same render node, if requested (the compositor runs as
# the wayland-wm@ unit, so add it to the drop-in omedora_uwsm_prepare wrote).
if [[ -n $NODE ]]; then
  echo "Environment=AQ_DRM_DEVICES=$NODE" \
    >>"$HOME/.config/systemd/user/wayland-wm@.service.d/10-nest.conf"
  systemctl --user daemon-reload 2>/dev/null || true
fi

# Run uwsm start detached so we can wait for IPC + create the headless output,
# then either block or return. The wayland-wm@ units it starts are
# systemd-managed and persist independently of this monitor process.
log "starting nested Hyprland via uwsm start (-> $HOST_WL)"
setsid uwsm start -- hyprland.desktop >"$XDG_RUNTIME_DIR/uwsm-start.log" 2>&1 &

# Wait for Hyprland's IPC socket.
SIG=""
for _ in $(seq 1 60); do
  SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
  [[ -n $SIG && -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]] && break
  [[ "$(systemctl --user is-active wayland-wm@hyprland.desktop.service 2>/dev/null)" == "failed" ]] && {
    echo "Hyprland (wayland-wm@hyprland.desktop) failed to start:" >&2
    journalctl --user -u wayland-wm@hyprland.desktop.service --no-pager | tail -20 >&2
    exit 1
  }
  sleep 0.5
done
[[ -n $SIG ]] || { echo "Hyprland never created its IPC socket" >&2; cat "$XDG_RUNTIME_DIR/uwsm-start.log" >&2; exit 1; }
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
log "Hyprland IPC up (instance $SIG)"

# --- 3. ensure a usable monitor --------------------------------------------
# The nested aquamarine output doesn't always promote to a Hyprland monitor on
# its own under this lionheartp v0.55.2 build, so create an explicit headless
# output. (`hyprctl keyword` is rejected by the Lua parser; `output create`
# works.)
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
    systemctl --user stop wayland-wm@hyprland.desktop.service omedora-labwc
================================================================
EOF

# --- 4. block (or return for scripted driving) ------------------------------
if [[ -n "${OMEDORA_HEADLESS_KEEP:-}" ]]; then
  log "session left running (OMEDORA_HEADLESS_KEEP set); returning."
  exit 0
fi

log "blocking until the session ends (Ctrl-C to stop)..."
while [[ "$(systemctl --user is-active wayland-wm@hyprland.desktop.service 2>/dev/null)" == "active" ]]; do
  sleep 2
done
log "session ended."
