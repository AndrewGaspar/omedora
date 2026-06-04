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

# --- 1g. GNOME session branch (interactive coexistence check) ----------------
# When asked for GNOME (run-session.sh --workstation --gnome), run GNOME Shell
# INSTEAD of the Omedora/Hyprland stack — the container-friendly stand-in for
# "log out of Hyprland, log into GNOME" (the real GDM greeter can't run in
# rootless nested podman: no seat/DRM master). GNOME Shell 50 dropped the old
# `--nested` flag and won't nest into another compositor, so we run mutter's OWN
# headless display server with a virtual monitor — a self-contained GNOME session
# on its own wayland socket (no labwc needed for this path). Best-effort /
# interactive: GNOME under software/llvmpipe rendering is heavy and NOT golden-imaged.
if [[ "$SESSION" == "gnome" ]]; then
  command -v gnome-shell >/dev/null || {
    echo "gnome-shell not installed — this needs the --workstation image" >&2; exit 2; }
  log "starting GNOME Shell (headless display server, virtual monitor $RES)"
  systemctl --user reset-failed omedora-gnome 2>/dev/null || true
  # gnome-shell needs its own session bus (dbus-run-session) for its many bus
  # services. --headless + --virtual-monitor gives a usable output without a seat
  # (mutter auto-picks the DRM render node passed via --device /dev/dri). NOTE:
  # plain `--wayland` would NOT nest into a parent compositor on mutter 50 — it
  # falls back to a headless native backend anyway — so we ask for it explicitly.
  systemd-run --user --quiet --unit=omedora-gnome \
    --setenv=XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    --setenv=XDG_CURRENT_DESKTOP=GNOME \
    --setenv=XDG_SESSION_TYPE=wayland \
    dbus-run-session -- gnome-shell --wayland --headless --virtual-monitor "$RES"

  # GNOME Shell opens its own wayland socket once mutter is up; wait for it (and
  # bail if the unit fails fast).
  GNOME_WL=""
  for _ in $(seq 1 40); do
    [[ "$(systemctl --user is-active omedora-gnome 2>/dev/null)" == "failed" ]] && {
      echo "GNOME Shell failed to start:" >&2
      journalctl --user -u omedora-gnome --no-pager | tail -30 >&2
      exit 1
    }
    GNOME_WL=$(ls "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
    [[ -n $GNOME_WL ]] && break
    sleep 0.5
  done
  [[ -n $GNOME_WL ]] && log "GNOME Shell up on socket: $GNOME_WL" \
    || log "GNOME Shell unit active but no wayland socket yet (continuing)"

  cat <<EOF

================ GNOME session is up ===========================
  GNOME Shell:  systemd --user unit 'omedora-gnome' (headless, virtual ${RES})
                WAYLAND_DISPLAY=${GNOME_WL:-<pending>}
  Proves GNOME runs as a selectable fallback alongside Omedora/Hyprland on the
  Workstation base. (The real GDM greeter/session-picker is an L4-VM thing.)
  Drive it (inside the container, as omedora):
    export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=${GNOME_WL:-wayland-0}
    # NB: grim won't work — Mutter has no wlr-screencopy. Use GNOME's own API:
    gdbus call --session -d org.gnome.Shell.Screenshot \\
      -o /org/gnome/Shell/Screenshot -m org.gnome.Shell.Screenshot.Screenshot \\
      true false /tmp/gnome.png
  Stop it:
    systemctl --user stop omedora-gnome
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
# Drive Hyprland directly via uwsm (no resolver .desktop) — matches
# default/wayland-sessions/omedora.desktop. We run `start-hyprland` (the upstream
# watchdog launcher; running bare `Hyprland` triggers its "started without
# start-hyprland" warning). The uwsm unit instance is derived from the command
# basename "start-hyprland" -> wayland-wm@start\x2dhyprland.service (was
# hyprland.desktop). $WM_UNIT below tracks that name.
setsid uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland >"$XDG_RUNTIME_DIR/uwsm-start.log" 2>&1 &

# The compositor systemd unit uwsm generates. uwsm escapes the command basename
# ("start-hyprland") the systemd way ("-" -> "\x2d"), so the instance is
# start\x2dhyprland. systemd-escape resolves it robustly regardless of uwsm's
# escaping rules; fall back to the known literal if systemd-escape is absent.
WM_UNIT=$(systemd-escape --template=wayland-wm@.service "start-hyprland" 2>/dev/null) \
  || WM_UNIT='wayland-wm@start\x2dhyprland.service'

# Wait for Hyprland's IPC socket.
SIG=""
for _ in $(seq 1 60); do
  SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
  [[ -n $SIG && -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ]] && break
  [[ "$(systemctl --user is-active "$WM_UNIT" 2>/dev/null)" == "failed" ]] && {
    echo "Hyprland ($WM_UNIT) failed to start:" >&2
    journalctl --user -u "$WM_UNIT" --no-pager | tail -20 >&2
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
    systemctl --user stop $WM_UNIT omedora-labwc
================================================================
EOF

# --- 4. block (or return for scripted driving) ------------------------------
if [[ -n "${OMEDORA_HEADLESS_KEEP:-}" ]]; then
  log "session left running (OMEDORA_HEADLESS_KEEP set); returning."
  exit 0
fi

log "blocking until the session ends (Ctrl-C to stop)..."
while [[ "$(systemctl --user is-active "$WM_UNIT" 2>/dev/null)" == "active" ]]; do
  sleep 2
done
log "session ended."
