#!/bin/bash
#
# L4-VM in-guest TAP runner: run the SAME headless assertion suite
# (omedora/test/fedora/headless/{lib.sh,tests/*.sh}) against the REAL graphical
# session GDM autologged the user into. Runs over SSH as the VM user; prints a
# TAP report; copies per-test artifacts under ~/vm-suite/artifacts.
#
# THE ATTACH PROBLEM. The podman tier enters the session with `machinectl shell`
# (which gives a fresh login scope with XDG_RUNTIME_DIR + a user bus). Over SSH
# we are NOT in the graphical session — we're a separate login. But the user's
# `systemd --user` manager and the Hyprland instance ARE running under
# /run/user/$UID. So we reconstruct the session env the tests need:
#   * XDG_RUNTIME_DIR=/run/user/$UID                 (the live runtime dir)
#   * DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus   (the user bus)
#   * HYPRLAND_INSTANCE_SIGNATURE / WAYLAND_DISPLAY  (lib.sh derives these from
#     $XDG_RUNTIME_DIR/hypr — already handled by headless_session_env)
# That is exactly the env `machinectl shell` would have set, so lib.sh's
# headless_session_env attaches identically. No test is modified.

set -uo pipefail

SUITE="$HOME/vm-suite"
TESTS="$SUITE/tests"
ART="$SUITE/artifacts"
LIB="$SUITE/lib.sh"

UID_NUM="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/$UID_NUM"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export XDG_CURRENT_DESKTOP="Hyprland"

# The committed visual goldens (30/40/50) are captured at the headless tier's
# 1920x1080 output; the VM renders at the virtio-gpu's advertised mode (often
# 1280x800), so a pixel-diff against the golden is a geometry mismatch, not a
# real regression. Downgrade those to TAP SKIPs in the VM tier — the session's
# actual rendering is proven by the host-side `virsh screenshot` + the
# layer/process assertions in 00/10/20. (Off in the podman tier; see lib.sh.)
# The orchestrator forwards OMEDORA_VM_GEOMETRY_SKIP here; 0 (paired with
# OMEDORA_VM_RES=1920x1080) turns the goldens back into real pass/fail. lib.sh
# only checks set-vs-unset, so 0 has to mean unset, not an exported "0".
export SCREENSHOT_GEOMETRY_SKIP="${SCREENSHOT_GEOMETRY_SKIP:-1}"
[[ "$SCREENSHOT_GEOMETRY_SKIP" == "0" ]] && unset SCREENSHOT_GEOMETRY_SKIP

rm -rf "$ART"; mkdir -p "$ART"

echo "# L4-VM session-attach suite"
echo "# XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"

# Sanity: is a Hyprland instance even up? If not, every test would fail the same
# way; report it once clearly.
if ! ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | grep -q .; then
  echo "# WARNING: no Hyprland instance under $XDG_RUNTIME_DIR/hypr — session not up?" >&2
  echo "# user units (failed):"
  systemctl --user list-units --failed --no-legend 2>/dev/null | sed 's/^/#   /' || true
fi

mapfile -t test_files < <(cd "$TESTS" 2>/dev/null && ls -1 *.sh 2>/dev/null | sort)
n=${#test_files[@]}
if (( n == 0 )); then
  echo "Bail out! no tests found under $TESTS" >&2
  exit 2
fi

echo
echo "1..$n"
passed=0; failed=0; failed_names=()
idx=0
for t in "${test_files[@]}"; do
  idx=$((idx + 1))
  name="${t%.sh}"
  art_dir="$ART/$name"
  mkdir -p "$art_dir"

  # Each test sources lib.sh and calls headless_session_env, which reads the env
  # we exported above. Run in a subshell with a per-test ARTIFACTS dir; capture
  # the real exit code (the tests `exit 1` on the first failed assertion).
  set +e
  out=$(ARTIFACTS="$art_dir" TEST_NAME="$name" \
        WALKER_TEST_ITERS="${WALKER_TEST_ITERS:-20}" \
        bash "$TESTS/$t" 2>&1)
  rc=$?
  set -e 2>/dev/null || true

  printf '%s\n' "$out" | sed 's/^/    /'
  if (( rc == 0 )); then
    echo "ok $idx - $name"
    passed=$((passed + 1))
  else
    echo "not ok $idx - $name"
    failed=$((failed + 1))
    failed_names+=("$name")
  fi
done

echo
echo "# tests $n"
echo "# pass  $passed"
echo "# fail  $failed"
if (( failed > 0 )); then
  echo "# failed: ${failed_names[*]}"
  exit 1
fi
echo "# all $passed session assertions passed"
exit 0
