#!/bin/bash
#
# L4-headless acceptance test for the Fedora wifi TUI (gazelle).
#
# Omarchy's wifi panel is impala, which drives iwd — but Fedora rides
# NetworkManager and ships no iwd, so omedora installs gazelle (a NetworkManager
# wifi TUI) and omarchy-launch-wifi launches it instead of impala on Fedora.
# Since the whole point is "the wifi TUI works in the omedora session," this
# test drives the real Super+Ctrl+W entry point and proves a gazelle window
# actually comes up — install correctness (the RPM landed) + chain correctness
# (the distro branch + launcher) + the TUI not crash-on-start, in one path.
#
# The L4 container is always Fedora, so this test is unconditional here (no
# distro SKIP-gate needed — unlike 90-workstation).
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

CLASS="org.omarchy.gazelle"
launch_pid=""

# Always tear the window + process down, even if an assertion fails mid-test
# (helpers.sh `fail` exits non-zero), so gazelle can't leak into a later test.
cleanup() {
  hyprctl dispatch closewindow "class:$CLASS" >/dev/null 2>&1 || true
  pkill -f "gazelle" >/dev/null 2>&1 || true
  [[ -n $launch_pid ]] && { kill "$launch_pid" >/dev/null 2>&1 || true; wait "$launch_pid" 2>/dev/null || true; }
}
trap cleanup EXIT

# 1. Package installed: gazelle on PATH. Proves the gazelle-tui RPM resolved and
#    installed from the local omedora repo during the packaging phase.
assert_output_contains "gazelle binary on PATH" "$(command -v gazelle 2>/dev/null)" "gazelle"

# 2. The launcher picks gazelle here. omarchy-launch-wifi branches on
#    omarchy-distro; the L4 container is Fedora, so the branch must resolve to
#    gazelle (on Arch it would launch impala instead).
assert_output_contains "omarchy-distro is fedora (launcher -> gazelle)" \
  "$(omarchy-distro 2>/dev/null)" "fedora"

# 3. Launch through the REAL entry point users trigger — Super+Ctrl+W, the
#    waybar network click, and the "Setup Wi-Fi" mako notification all call
#    omarchy-launch-wifi — and confirm a gazelle terminal window maps. Textual +
#    Python cold-start under llvmpipe is heavy, so allow a generous timeout.
omarchy-launch-wifi >/dev/null 2>&1 &
launch_pid=$!

wait_for_client "$CLASS" 20 || true
screenshot "${TEST_NAME}-gazelle"
assert_client "$CLASS" "omarchy-launch-wifi opens a gazelle window ($CLASS)"

# 4. gazelle is actually running — the terminal didn't open-then-die on a Python
#    import error / startup crash. A window can flash and vanish; a live process
#    after the window mapped is the stronger signal that the TUI came up.
assert_proc "gazelle" "gazelle process is alive (TUI started, did not crash)"

# 5. The window is floating — exercises the system.conf floating-window rule we
#    extended with org.omarchy.gazelle (impala/bluetui get the same treatment).
floating=$(hyprctl clients -j 2>/dev/null | python3 -c \
  'import sys,json; cs=json.load(sys.stdin); print(any(c.get("class")=="'"$CLASS"'" and c.get("floating") for c in cs))' \
  2>/dev/null)
assert_equals "gazelle window is floating (system.conf rule applied)" "$floating" "True"
