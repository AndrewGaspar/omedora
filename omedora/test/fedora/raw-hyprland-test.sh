#!/bin/bash
#
# L4 test: the VANILLA / "piggyback" Hyprland path.
#
# Proves that on a PLAIN Fedora 44 with NO omedora install and NO omedora
# config, the natural/discoverable full `hyprland` package (from the COPR
# agaspar/omedora-3.8.2) pulls the binaries package `hyprland-no-session` and
# boots a DEFAULT Hyprland session using Hyprland's BUILT-IN config — no uwsm,
# no ~/.config/hypr, no seeded config.
#
# This validates the Hyprland subpackage split end-to-end from a piggybacker's
# point of view:
#   1. `dnf install hyprland`  → drags in `hyprland-no-session` (the binaries),
#      and the FULL package owns the plain wayland-sessions/hyprland.desktop.
#   2. `hyprland-no-session` is self-sufficient as the binaries package: the raw
#      `start-hyprland` launcher boots a working compositor with NOTHING from
#      omedora — Hyprland's compiled-in defaults are enough.
#
# How it nests (mirrors omedora/test/fedora/omedora-session/session-launch-headless.sh):
#   A throwaway podman fedora:44 systemd container stands up its OWN headless
#   Wayland host (labwc, wlroots headless backend) and nests RAW Hyprland into
#   labwc's socket via Aquamarine's "wayland" (nested) backend. Unlike the
#   omedora launcher this path deliberately does NOT use uwsm and does NOT seed
#   any config — it runs `start-hyprland` directly with HYPRLAND_CONFIG pointed
#   at an EMPTY file so Hyprland falls back to its built-in defaults.
#
#   labwc is the nesting host (not weston/sway/cage) for the same reason as the
#   omedora headless launcher: Aquamarine 0.12's nested backend HARD-REQUIRES
#   the host to advertise xdg_wm_base v6 AND zwp_linux_dmabuf_v1, which labwc
#   0.9.6 (wlroots 0.19) does and weston/sway do not. See omedora/testing.md.
#
# Standalone — does NOT depend on the prebuilt omedora session image. It builds
# its own minimal "vanilla Fedora + labwc + a login user" image, then does the
# dnf copr enable / dnf install INSIDE that container so the COPR resolution is
# exercised live. Safe to run on its own:
#
#   omedora/test/fedora/raw-hyprland-test.sh
#   omedora/test/fedora/raw-hyprland-test.sh --keep      # leave the container up
#   omedora/test/fedora/raw-hyprland-test.sh --rebuild   # rebuild the vanilla image
#
# Requirements: podman with --systemd support and a DRM render node
# (--device /dev/dri). For GPU-less CI: `sudo modprobe vkms`, then
# OMEDORA_RENDER_NODE=/dev/dri/renderD<n>. Host is Arch — uses podman fedora:44.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
HELPERS="$REPO/test/helpers.sh"
# shellcheck source=/dev/null
. "$HELPERS"

COPR_PROJECT="${RAW_HYPR_COPR:-$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr")}"
IMAGE="${RAW_HYPR_IMAGE:-omedora-test:fedora44-raw-hyprland}"
CTR="${RAW_HYPR_CTR:-omedora-raw-hyprland-$$}"
RES="${OMEDORA_HEADLESS_RES:-1920x1080}"
NODE="${OMEDORA_RENDER_NODE:-}"

# Default /tmp has a tiny quota in this environment; podman needs a real TMPDIR.
export TMPDIR="${TMPDIR:-/var/tmp/podman-tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

keep=false; rebuild=false
for arg in "$@"; do
  case "$arg" in
    --keep)    keep=true ;;
    --rebuild) rebuild=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m[raw-hypr]\033[0m %s\n' "$*"; }

# --- build a VANILLA Fedora 44 image (no omedora) ----------------------------
# A real PID-1 systemd container so we get logind + per-user `systemd --user`
# (labwc runs as a transient user unit, exactly like the omedora headless
# launcher). The ONLY desktop bits baked in are labwc (the nesting host) — NO
# Hyprland, NO omedora: hyprland is installed live inside the container so the
# COPR resolution is part of the test.
build_image() {
  log "Building vanilla Fedora 44 image '$IMAGE' (labwc host, no omedora)..."
  local ctx; ctx=$(mktemp -d "$TMPDIR/raw-hypr-ctx.XXXXXX")
  cat >"$ctx/Dockerfile" <<'DOCKERFILE'
FROM registry.fedoraproject.org/fedora:44

# PID-1 systemd + logind + a system bus, plus dnf copr support and the small set
# of tools the test drives (jq/python for hyprctl JSON, procps for pgrep).
RUN dnf install -y --setopt=install_weak_deps=False \
        systemd systemd-container systemd-pam dbus-broker polkit \
        dnf-plugins-core \
        jq python3 procps-ng findutils which util-linux \
    && dnf clean all

# labwc = the headless Wayland host RAW Hyprland nests into. The lightest Fedora
# 44 compositor advertising the protocols Aquamarine's nested backend needs
# (xdg_wm_base v6 + zwp_linux_dmabuf_v1). TEST scaffolding only.
RUN dnf install -y --setopt=install_weak_deps=False labwc wayland-utils \
    && dnf clean all \
    # labwc ships cap_sys_nice (file cap); not in rootless podman's user-ns
    # bounding set, so `systemd-run --user labwc` would fail 203 at exec. Strip it.
    && (setcap -r /usr/bin/labwc || true)

# Container-friendly systemd: mask units that error in a rootless container so
# `systemctl is-system-running` settles quickly.
RUN systemctl mask \
        systemd-remount-fs.service systemd-machine-id-commit.service \
        dev-hugepages.mount sys-kernel-config.mount sys-kernel-debug.mount || true
RUN systemctl enable dbus-broker.service systemd-logind.service || true

# user@.service needs XDG_RUNTIME_DIR when started by linger pre-login.
RUN mkdir -p /etc/systemd/system/user@.service.d && \
    printf '[Service]\nEnvironment=XDG_RUNTIME_DIR=/run/user/%%i\n' \
        >/etc/systemd/system/user@.service.d/10-xdg-runtime-dir.conf

# A login user (uid 1000) with passwordless sudo so `dnf copr enable` / install
# run from inside the logind session.
RUN useradd --create-home --uid 1000 --shell /bin/bash --groups wheel tester && \
    printf '%%wheel ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/wheel-nopasswd && \
    chmod 0440 /etc/sudoers.d/wheel-nopasswd

# Linger so `systemd --user` for the user comes up at boot.
RUN install -d -m 0755 /var/lib/systemd/linger && touch /var/lib/systemd/linger/tester

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
DOCKERFILE
  podman build -t "$IMAGE" "$ctx"
  local rc=$?
  rm -rf "$ctx"
  return $rc
}

if $rebuild || ! podman image exists "$IMAGE"; then
  build_image || { echo "image build failed" >&2; exit 1; }
fi

# --- boot the container ------------------------------------------------------
cleanup() {
  if $keep; then
    log "Container '$CTR' left running (--keep). Remove with: podman rm -f $CTR"
  else
    # Stop the session units first (tidy), then remove the container.
    podman exec "$CTR" machinectl shell tester@.host /bin/bash -c \
      'systemctl --user stop raw-hyprland raw-labwc 2>/dev/null || true' >/dev/null 2>&1 || true
    podman rm -f "$CTR" >/dev/null 2>&1 || true
  fi
  [[ -n "${LAUNCHER_HOST:-}" ]] && rm -f "$LAUNCHER_HOST" 2>/dev/null || true
}
trap cleanup EXIT
podman rm -f "$CTR" >/dev/null 2>&1 || true

run_args=(-d --name "$CTR" --systemd=always --device /dev/dri)
[[ -e /dev/rfkill ]] && run_args+=(--device /dev/rfkill)

log "Booting '$IMAGE' as container '$CTR'..."
podman run "${run_args[@]}" "$IMAGE" >/dev/null || { echo "podman run failed" >&2; exit 1; }

log "Waiting for systemd + user@1000 manager..."
for i in $(seq 1 90); do
  state=$(podman exec "$CTR" systemctl is-system-running 2>/dev/null || true)
  case "$state" in running|degraded) break ;; esac
  [[ $i -eq 90 ]] && { echo "systemd never settled (last: ${state:-none})" >&2; podman logs "$CTR" | tail -20 >&2; exit 1; }
  sleep 1
done
for i in $(seq 1 30); do
  [[ "$(podman exec "$CTR" systemctl is-active user@1000.service 2>/dev/null || true)" == active ]] && break
  [[ $i -eq 30 ]] && { echo "user@1000.service never active" >&2; exit 1; }
  sleep 1
done
log "  systemd: $state, user@1000: active"

# Convenience: run a command in the container as root.
cexec() { podman exec "$CTR" "$@"; }
# Run a command inside the tester logind session (real XDG_RUNTIME_DIR + bus).
# machinectl shell always exits 0, so callers that need rc use the sentinel
# pattern; for the launch we background it and poll state from the host.

echo
echo "# --- 1. COPR resolution: dnf install hyprland pulls the binaries ---"

# Enable the COPR and install the FULL/discoverable package.
log "dnf copr enable $COPR_PROJECT ..."
if ! cexec dnf -y copr enable "$COPR_PROJECT" >/tmp/raw-hypr-copr.log 2>&1; then
  cat /tmp/raw-hypr-copr.log >&2
  fail "dnf copr enable $COPR_PROJECT"
fi
pass "dnf copr enable $COPR_PROJECT"

log "dnf install -y hyprland (the FULL package) ..."
inst_out=$(cexec dnf install -y hyprland 2>&1)
inst_rc=$?
printf '%s\n' "$inst_out" | tail -40 | sed 's/^/    /'
[[ $inst_rc -eq 0 ]] || fail "dnf install -y hyprland (rc=$inst_rc)"
pass "dnf install -y hyprland"

# Both packages present: the full one AND the binaries it dragged in.
qfull=$(cexec rpm -q hyprland 2>/dev/null)
qbase=$(cexec rpm -q hyprland-no-session 2>/dev/null)
assert_output_contains "hyprland (full package) installed"        "$qfull" "hyprland-"
assert_output_contains "hyprland-no-session (binaries) pulled in" "$qbase" "hyprland-no-session-"

# The full package owns the plain, visible session entry.
owner=$(cexec rpm -qf /usr/share/wayland-sessions/hyprland.desktop 2>/dev/null)
assert_output_contains "/usr/share/wayland-sessions/hyprland.desktop owned by hyprland" \
  "$owner" "hyprland-"
# ...and it's the FULL package, not the binaries package (sanity: the split held).
if [[ "$owner" == hyprland-no-session-* ]]; then
  fail "hyprland.desktop must be owned by the FULL package, not hyprland-no-session (got: $owner)"
fi
pass "hyprland.desktop is owned by the full package, not hyprland-no-session"

# The binaries package supplies the launcher + IPC we boot/assert with.
for b in Hyprland start-hyprland hyprctl; do
  bowner=$(cexec rpm -qf "/usr/bin/$b" 2>/dev/null || true)
  assert_output_contains "/usr/bin/$b provided by hyprland-no-session" \
    "$bowner" "hyprland-no-session-"
done

echo
echo "# --- 2. launch RAW Hyprland (default config, no uwsm, no ~/.config/hypr) ---"

# Make ABSOLUTELY sure there is no user Hyprland config: the test must exercise
# Hyprland's compiled-in defaults. We point HYPRLAND_CONFIG at an EMPTY file
# (and pin XDG_CONFIG_HOME at an empty dir) so even a future packaged
# /etc default can't sneak in. An empty config => built-in defaults.
cexec su - tester -c 'rm -rf ~/.config/hypr ~/.config/uwsm; mkdir -p ~/raw-cfg/empty; : > ~/raw-cfg/empty.conf' \
  >/dev/null 2>&1 || true

# The launch script we drop into the container and run inside the tester logind
# session. It stands up labwc (headless), then runs `start-hyprland` DIRECTLY
# (no uwsm) with Aquamarine's nested wayland backend pointed at labwc's socket,
# and Hyprland's built-in default config (empty HYPRLAND_CONFIG).
RENDER_NODE_ENV=""
[[ -n "$NODE" ]] && RENDER_NODE_ENV="$NODE"
LAUNCHER=/home/tester/raw-launch.sh
# Generate the launcher on the HOST, then podman cp it in. (Piping a heredoc to
# `podman exec ... tee` would need `podman exec -i`; copying a file is robust.)
LAUNCHER_HOST=$(mktemp "$TMPDIR/raw-launch.XXXXXX.sh")
cat >"$LAUNCHER_HOST" <<LAUNCH
#!/bin/bash
set -uo pipefail
: "\${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR}"
RES="$RES"
NODE="$RENDER_NODE_ENV"

# --- 1. headless host compositor (labwc), as a transient user unit -----------
labwc_node_env=()
[[ -n "\$NODE" ]] && labwc_node_env=(--setenv=WLR_RENDER_DRM_DEVICE="\$NODE")
systemctl --user reset-failed raw-labwc 2>/dev/null || true
systemd-run --user --quiet --unit=raw-labwc \\
  --setenv=XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \\
  --setenv=WLR_BACKENDS=headless \\
  --setenv=WLR_LIBINPUT_NO_DEVICES=1 \\
  --setenv=WLR_RENDERER_ALLOW_SOFTWARE=1 \\
  "\${labwc_node_env[@]}" \\
  labwc

HOST_WL=""
for _ in \$(seq 1 30); do
  HOST_WL=\$(ls "\$XDG_RUNTIME_DIR" 2>/dev/null | grep -E '^wayland-[0-9]+\$' | head -1)
  [[ -n \$HOST_WL ]] && break
  [[ "\$(systemctl --user is-active raw-labwc)" == failed ]] && {
    echo "labwc failed:" >&2; journalctl --user -u raw-labwc --no-pager | tail -20 >&2; exit 1; }
  sleep 0.5
done
[[ -n \$HOST_WL ]] || { echo "labwc never created a socket" >&2; exit 1; }
echo "[raw-launch] labwc up on host socket: \$HOST_WL"

# --- 2. RAW Hyprland nested into labwc, NO uwsm, built-in default config ------
# Aquamarine nested ("wayland") backend → connect to labwc's WAYLAND_DISPLAY.
# HYPRLAND_CONFIG points at an EMPTY file so Hyprland uses its compiled-in
# defaults (no ~/.config/hypr, no omedora config, nothing seeded).
#
# Run start-hyprland under \`systemd-run --user\` (NOT uwsm) so the compositor
# lives in its own user scope that survives this \`machinectl shell\` returning —
# the shell's session scope is torn down on exit and would kill a bare
# backgrounded child. This is plain systemd-run, not a uwsm-managed session:
# no env propagation to the user manager, no autostart, just the raw binary.
rm -f "\$XDG_RUNTIME_DIR/raw-hypr.log"
node_env=()
[[ -n "\$NODE" ]] && node_env=(--setenv=AQ_DRM_DEVICES="\$NODE")
systemctl --user reset-failed raw-hyprland 2>/dev/null || true
systemd-run --user --quiet --unit=raw-hyprland \\
  --setenv=XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \\
  --setenv=WAYLAND_DISPLAY="\$HOST_WL" \\
  --setenv=AQ_BACKENDS=wayland \\
  --setenv=WLR_BACKENDS=wayland \\
  --setenv=XDG_CONFIG_HOME="\$HOME/raw-cfg" \\
  --setenv=HYPRLAND_CONFIG="\$HOME/raw-cfg/empty.conf" \\
  --setenv=XDG_CURRENT_DESKTOP=Hyprland \\
  "\${node_env[@]}" \\
  -p StandardOutput=append:"\$XDG_RUNTIME_DIR/raw-hypr.log" \\
  -p StandardError=append:"\$XDG_RUNTIME_DIR/raw-hypr.log" \\
  /usr/bin/start-hyprland
echo "[raw-launch] start-hyprland launched (systemd --user unit raw-hyprland)"

# Wait for Hyprland's IPC socket.
SIG=""
for _ in \$(seq 1 60); do
  SIG=\$(ls -t "\$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
  [[ -n \$SIG && -S "\$XDG_RUNTIME_DIR/hypr/\$SIG/.socket.sock" ]] && break
  [[ "\$(systemctl --user is-active raw-hyprland 2>/dev/null)" == failed ]] && {
    echo "raw-hyprland unit failed:" >&2
    journalctl --user -u raw-hyprland --no-pager 2>/dev/null | tail -30 >&2
    cat "\$XDG_RUNTIME_DIR/raw-hypr.log" 2>/dev/null >&2; exit 1; }
  sleep 0.5
done
[[ -n \$SIG ]] || { echo "Hyprland never created its IPC socket" >&2; cat "\$XDG_RUNTIME_DIR/raw-hypr.log" >&2; exit 1; }
echo "[raw-launch] Hyprland IPC up (instance \$SIG)"
echo "\$SIG" > "\$XDG_RUNTIME_DIR/raw-hypr.sig"

# --- 3. ensure a usable monitor ----------------------------------------------
# The nested aquamarine output doesn't always self-promote to a Hyprland monitor
# under this build; create an explicit headless output (same technique as the
# omedora headless launcher).
export HYPRLAND_INSTANCE_SIGNATURE="\$SIG"
sleep 1
hyprctl output create headless >/dev/null 2>&1 || true
for _ in \$(seq 1 10); do
  n=\$(hyprctl monitors -j 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  [[ "\$n" -ge 1 ]] && break
  sleep 0.5
done
echo "[raw-launch] session up; leaving it running."
exit 0
LAUNCH
podman cp "$LAUNCHER_HOST" "$CTR:$LAUNCHER"
rm -f "$LAUNCHER_HOST"
cexec chown tester:tester "$LAUNCHER"
cexec chmod +x "$LAUNCHER"

log "Launching raw Hyprland inside the tester logind session..."
launch_out=$(cexec machinectl shell --setenv=TERM=dumb tester@.host "$LAUNCHER" 2>&1)
printf '%s\n' "$launch_out" | sed 's/^/    /'

# The launcher writes the instance signature to a sentinel on success.
SIG=$(cexec cat /run/user/1000/raw-hypr.sig 2>/dev/null | tr -d '[:space:]')
if [[ -z "$SIG" ]]; then
  echo "raw Hyprland never came up; launcher log:" >&2
  cexec cat /run/user/1000/raw-hypr.log 2>/dev/null | sed 's/^/    /' >&2 || true
  fail "raw Hyprland nested launch (no IPC instance)"
fi
pass "raw Hyprland nested launch produced an IPC instance ($SIG)"

echo
echo "# --- 3. assert raw Hyprland reasonably started ---"

# Helper to run hyprctl in the session with the right instance signature.
hc() {
  cexec machinectl shell --setenv=HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
    tester@.host /usr/bin/hyprctl "$@" 2>/dev/null
}

# 3a. hyprctl version responds (proves the IPC socket answers).
ver=$(hc version)
assert_output_contains "hyprctl version responds" "$ver" "Hyprland"

# 3b. at least one monitor.
mon_json=$(cexec machinectl shell --setenv=HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
  tester@.host /usr/bin/hyprctl monitors -j 2>/dev/null)
nmon=$(printf '%s' "$mon_json" | python3 -c 'import sys,json
try: print(len(json.load(sys.stdin)))
except Exception: print(0)' 2>/dev/null)
echo "    hyprctl monitors -j => $nmon monitor(s):"
printf '%s\n' "$mon_json" | python3 -m json.tool 2>/dev/null | sed 's/^/      /' || printf '%s\n' "$mon_json" | sed 's/^/      /'
if [[ "${nmon:-0}" -ge 1 ]]; then
  pass "hyprctl monitors shows >=1 monitor ($nmon)"
else
  fail "hyprctl monitors shows >=1 monitor (got: ${nmon:-0})"
fi

# 3c. NOT in Safe Mode and no crash in the log. Hyprland enters Safe Mode when
# the config fails to load / a plugin crashes; the built-in default config must
# NOT trip it. Check both the log and hyprctl's reported state.
hlog=$(cexec cat /run/user/1000/raw-hypr.log 2>/dev/null)
if printf '%s' "$hlog" | grep -qi 'safe mode'; then
  echo "    log mentions Safe Mode:" >&2
  printf '%s\n' "$hlog" | grep -i 'safe mode' | sed 's/^/      /' >&2
  fail "raw Hyprland did NOT enter Safe Mode"
fi
pass "raw Hyprland did NOT enter Safe Mode (none in log)"

# 3d. the compositor process is still alive (didn't crash immediately).
if cexec pgrep -x Hyprland >/dev/null 2>&1; then
  pass "Hyprland process alive after startup"
else
  # Fall back to a fuzzy match (start-hyprland may exec/rename).
  if cexec pgrep -f '[H]yprland' >/dev/null 2>&1; then
    pass "Hyprland process alive after startup (fuzzy match)"
  else
    fail "Hyprland process alive after startup"
  fi
fi

# 3e. for good measure: the default-config path really had no user config.
nocfg=$(cexec su - tester -c 'test -e ~/.config/hypr/hyprland.conf && echo present || echo absent')
assert_equals "no ~/.config/hypr/hyprland.conf was used (built-in defaults)" "$nocfg" "absent"

echo
log "ALL ASSERTIONS PASSED — vanilla 'dnf install hyprland' boots a default session."
echo
echo "# Evidence summary:"
echo "#   full pkg:   $qfull"
echo "#   binaries:   $qbase"
echo "#   .desktop:   owned by $owner"
echo "#   hyprctl:    $(printf '%s' "$ver" | head -1)"
echo "#   monitors:   $nmon"
echo "#   Safe Mode:  none in log"
