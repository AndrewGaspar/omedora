#!/bin/bash
#
# L4-headless automated test suite — host orchestrator.
#
# Boots ONE self-contained headless Omedora v4 session container (the same path
# as `run-session.sh --headless`: labwc + nested Hyprland + the Quickshell
# shell, no host desktop, no socket bind-mount), copies the test library +
# suite into it, runs each tests/*.sh inside the logind session capturing TAP
# output + exit code, aggregates into a TAP report, copies artifacts out for
# any failing test, and exits non-zero iff any test failed. This is the
# canonical CI gate for L4 assertions.
#
# Each run uses a UNIQUE container name (omedora-htest-$$), so two invocations
# run concurrently without colliding — the headless session brings its own
# compositor, so there's no shared host socket to fight over.
#
# Usage:
#   omedora/test/fedora/headless/run-tests.sh                 # build if missing, run all
#   omedora/test/fedora/headless/run-tests.sh --rebuild       # rebuild the image first
#   omedora/test/fedora/headless/run-tests.sh --keep          # leave the container up
#   omedora/test/fedora/headless/run-tests.sh --test '10-*'   # run a subset (glob)
#   omedora/test/fedora/headless/run-tests.sh --workstation   # run the suite on a Fedora
#                                            #   Workstation base (00-50 + the SKIP-gated
#                                            #   90-workstation coexistence test)
#
# Requirements: podman with --systemd support and a DRM render node
# (--device /dev/dri). On GPU-less CI: `sudo modprobe vkms`, then
# OMEDORA_RENDER_NODE=/dev/dri/renderD<n>. See omedora/testing.md §6.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)
HEADLESS_DIR="$REPO/omedora/test/fedora/headless"
ARTIFACTS_DIR="$HEADLESS_DIR/artifacts"
# SESSION_IMAGE / CTR are resolved after arg parsing so --workstation can select
# the "-workstation" image lineage + a distinct (ws-) container name, letting a
# Workstation run and a standard run run concurrently.

# Default /tmp has a tiny quota in this environment; podman needs a real TMPDIR.
export TMPDIR="${TMPDIR:-/var/tmp/podman-tmp}"
mkdir -p "$TMPDIR"

LAUNCH_DIR_IN_IMAGE=/home/omedora/.local/share/omarchy/omedora/test/fedora/omedora-session
LAUNCH_HEADLESS_IN_IMAGE="$LAUNCH_DIR_IN_IMAGE/session-launch-headless.sh"
# Where we drop the suite inside the container (omedora-owned, on PATH-free tmp).
SUITE_IN_CTR=/home/omedora/headless-suite

rebuild=false; keep=false; test_glob='*.sh'; workstation=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)     rebuild=true ;;
    --keep)        keep=true ;;
    --test)        shift; test_glob="$1" ;;
    --workstation) workstation=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Resolve image + container names (after parsing, so --workstation applies). The
# Workstation run gets a "ws-" container prefix so it never collides with a
# concurrent standard run. Explicit OMEDORA_* env still wins.
variant=""; ctr_variant=""; $workstation && { variant="-workstation"; ctr_variant="ws-"; }
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-omedora-test:fedora44-session-4${variant}}"
CTR="${OMEDORA_HTEST_CTR:-omedora-htest-${ctr_variant}$$}"

log() { printf '\033[1;34m[htest]\033[0m %s\n' "$*"; }

# --- build the image if needed -----------------------------------------------
if $rebuild || ! podman image exists "$SESSION_IMAGE"; then
  log "Building session image..."
  build_flags=(); $rebuild && build_flags+=(--rebuild); $workstation && build_flags+=(--workstation)
  "$REPO/omedora/test/fedora/build-session.sh" "${build_flags[@]}"
fi

# --- boot one headless container ---------------------------------------------
cleanup() {
  if ! $keep; then
    podman rm -f "$CTR" >/dev/null 2>&1 || true
  else
    log "Container '$CTR' left running (--keep). Remove with: podman rm -f $CTR"
  fi
}
trap cleanup EXIT

podman rm -f "$CTR" >/dev/null 2>&1 || true

run_args=(-d --name "$CTR" --systemd=always --device /dev/dri)
# SELinux-enforcing hosts (default Fedora): systemd inside the container sets up
# mount namespacing over /proc and cgroupfs for sandboxed services (logind,
# polkit, upower); container_init_t is denied those mounts (AVC: mounton
# proc_t/cgroup_t), logind crashloops with 226/NAMESPACE and user@1000 never
# starts. Like the SYS_ADMIN grant below, this is test scaffolding, not the
# omedora product — run the container unconfined. No-op where SELinux is off.
run_args+=(--security-opt label=disable)
[[ -e /dev/rfkill ]] && run_args+=(--device /dev/rfkill)
# xdg-document-portal FUSE-mounts a document store at /run/user/1000/doc. That
# needs BOTH /dev/fuse AND the ability to call mount(2): rootless podman's
# user-ns has no CAP_SYS_ADMIN by default, so fusermount3's mount fails with
# "Operation not permitted" (status 6/NOTCONFIGURED) and the unit ends up
# `failed` — even though /dev/fuse is present. --cap-add SYS_ADMIN gives the
# user-ns the mount capability, so document-portal starts cleanly (verified:
# `portal on /run/user/1000/doc type fuse.portal`). On bare-metal Fedora the
# real user session already has this; the cap only re-grants what the rootless
# container drops. This is test scaffolding (the L4 harness), not the omedora
# product — it touches no /etc and no system policy.
if [[ -e /dev/fuse ]]; then
  run_args+=(--device /dev/fuse --cap-add SYS_ADMIN)
fi
# Iterate on the launch scripts without rebuilding the image.
run_args+=(-v "$REPO/omedora/test/fedora/omedora-session/session-launch-headless.sh:$LAUNCH_HEADLESS_IN_IMAGE:ro")
run_args+=(-v "$REPO/omedora/test/fedora/omedora-session/session-launch-common.sh:$LAUNCH_DIR_IN_IMAGE/session-launch-common.sh:ro")

log "Booting $SESSION_IMAGE as container '$CTR'..."
podman run "${run_args[@]}" "$SESSION_IMAGE" >/dev/null

log "Waiting for systemd + omedora user manager..."
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

# --- launch the headless session (returns once up; OMEDORA_HEADLESS_KEEP) -----
log "Launching the headless Omedora session..."
setenv_args=(--setenv=OMEDORA_HEADLESS_KEEP=1)
[[ -n "${OMEDORA_RENDER_NODE:-}" ]] && setenv_args+=(--setenv=OMEDORA_RENDER_NODE="$OMEDORA_RENDER_NODE")
[[ -n "${OMEDORA_HEADLESS_RES:-}" ]] && setenv_args+=(--setenv=OMEDORA_HEADLESS_RES="$OMEDORA_HEADLESS_RES")
if ! podman exec "$CTR" machinectl shell "${setenv_args[@]}" \
       omedora@.host "$LAUNCH_HEADLESS_IN_IMAGE"; then
  echo "headless session launch failed" >&2
  podman exec "$CTR" cat /run/user/1000/uwsm-start.log 2>/dev/null >&2 || true
  exit 1
fi

# --- copy the suite into the container ---------------------------------------
# Drop lib.sh + tests/ into an omedora-owned dir so the omedora session shell
# can read+run them (machinectl shell runs as omedora).
podman exec "$CTR" rm -rf "$SUITE_IN_CTR"
podman exec "$CTR" mkdir -p "$SUITE_IN_CTR/tests" "$SUITE_IN_CTR/fixtures"
podman cp "$HEADLESS_DIR/lib.sh"   "$CTR:$SUITE_IN_CTR/lib.sh"
podman cp "$HEADLESS_DIR/tests/."  "$CTR:$SUITE_IN_CTR/tests/"
# Committed fixtures (e.g. the 30-visual reference screenshot) the tests diff
# against. Optional — only present once a visual test ships.
if [[ -d "$HEADLESS_DIR/fixtures" ]]; then
  podman cp "$HEADLESS_DIR/fixtures/." "$CTR:$SUITE_IN_CTR/fixtures/"
fi
podman exec "$CTR" chown -R omedora:omedora "$SUITE_IN_CTR"

# --- discover + run tests -----------------------------------------------------
mapfile -t tests < <(cd "$HEADLESS_DIR/tests" && ls -1 $test_glob 2>/dev/null | sort)
n=${#tests[@]}
if (( n == 0 )); then
  echo "no tests matched: $test_glob" >&2
  exit 2
fi

rm -rf "$ARTIFACTS_DIR"
mkdir -p "$ARTIFACTS_DIR"

echo
echo "1..$n"
passed=0; failed=0; failed_names=()
idx=0
for t in "${tests[@]}"; do
  idx=$((idx + 1))
  name="${t%.sh}"
  art_in_ctr="$SUITE_IN_CTR/artifacts/$name"
  podman exec "$CTR" su - omedora -c "rm -rf '$art_in_ctr'; mkdir -p '$art_in_ctr'" >/dev/null 2>&1 || true

  # Run the test inside the logind session as omedora. machinectl shell gives a
  # real XDG_RUNTIME_DIR + user bus; the test sources lib.sh and attaches.
  #
  # IMPORTANT: `machinectl shell` ALWAYS exits 0 regardless of the child's exit
  # code (it reports the PTY-forwarding result, not the program's). So we can't
  # trust its rc — instead the inner shell writes the test's real exit code to a
  # sentinel file in the (omedora-owned) artifacts dir, which we read back.
  rc_file="$art_in_ctr/.exit-code"
  set +e
  out=$(podman exec "$CTR" machinectl shell \
        --setenv=ARTIFACTS="$art_in_ctr" \
        --setenv=TEST_NAME="$name" \
        --setenv=SHELL_TOGGLE_ITERS="${SHELL_TOGGLE_ITERS:-5}" \
        omedora@.host /bin/bash -c \
          "/bin/bash '$SUITE_IN_CTR/tests/$t'; echo \$? >'$rc_file'" 2>&1)
  rc=$(podman exec "$CTR" cat "$rc_file" 2>/dev/null)
  set -e
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=1   # missing/garbled sentinel => treat as failure

  # Echo the test's TAP/diagnostic lines, indented, for the log.
  printf '%s\n' "$out" | sed 's/^/    /'

  if (( rc == 0 )); then
    echo "ok $idx - $name"
    passed=$((passed + 1))
  else
    echo "not ok $idx - $name"
    failed=$((failed + 1))
    failed_names+=("$name")
    # Copy this test's artifacts out to the host.
    mkdir -p "$ARTIFACTS_DIR/$name"
    podman cp "$CTR:$art_in_ctr/." "$ARTIFACTS_DIR/$name/" 2>/dev/null || true
  fi
done

# --- summary ------------------------------------------------------------------
echo
echo "# tests $n"
echo "# pass  $passed"
echo "# fail  $failed"
if (( failed > 0 )); then
  echo "# failed: ${failed_names[*]}"
  echo "# artifacts: $ARTIFACTS_DIR/"
  exit 1
fi
log "all $passed tests passed"
exit 0
