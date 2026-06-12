#!/bin/bash
#
# L4-headless acceptance test for the v4 app launcher (Super+Space).
#
# The SUPER+SPACE bind (default/hypr/bindings/utilities.lua:
#   o.bind("SUPER + SPACE", "Launch apps", "omarchy-shell shell toggle
#   omarchy.launcher \"{}\"")
# ) toggles the `omarchy.launcher` Quickshell plugin over IPC. This test drives
# exactly that command and asserts the launcher's layer surface
# (`omarchy-launcher`, shell/plugins/launcher/Launcher.qml) maps — and that a
# second toggle unmaps it again.
#
# This replaces the 3.8.2-era 10-walker.sh: walker is retired on the v4 line;
# the launcher is an in-process shell plugin, summoned/hidden via IPC instead
# of spawning a client. The old test hammered walker 20x because its
# daemon-forwarded render was flaky; the in-process plugin has no such daemon
# race, but we still loop a few toggle cycles (SHELL_TOGGLE_ITERS, default 5)
# so a render that only works on the first summon can't sneak past.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

ITERS="${SHELL_TOGGLE_ITERS:-5}"
NS=omarchy-launcher

# The shell must be answering IPC before toggling means anything.
wait_for_shell_ping 30 || true
assert_shell_ping "shell answers ping before driving the launcher"

# One open/close cycle via the exact bind command. Returns 0 if the layer
# mapped AND unmapped on cue.
toggle_once() {
  omarchy-shell shell toggle omarchy.launcher "{}" >/dev/null 2>&1
  wait_for_layer "$NS" 10 || return 1
  omarchy-shell shell toggle omarchy.launcher "{}" >/dev/null 2>&1
  wait_for_layer_gone "$NS" 10 || return 2
  return 0
}

ok=0
for i in $(seq 1 "$ITERS"); do
  if toggle_once; then
    ok=$((ok + 1))
  else
    # Capture artifacts from the first failure for debugging.
    [[ $ok -eq $((i - 1)) ]] && { screenshot "${TEST_NAME}-miss-$i"; dump_state "${TEST_NAME}-miss-$i"; }
    # Best-effort: make sure the launcher is closed before the next iteration.
    omarchy-shell shell hide omarchy.launcher >/dev/null 2>&1 || true
    wait_for_layer_gone "$NS" 5 || true
  fi
done

printf '# launcher toggle cycles: %d/%d mapped+unmapped cleanly\n' "$ok" "$ITERS"

# Hard gate: every single toggle cycle must map and unmap the launcher layer.
assert_equals "launcher toggles cleanly on every cycle ($ok/$ITERS)" "$ok" "$ITERS"

# Leave the launcher open and prove `summon` is idempotent-visible, then hide.
omarchy-shell shell summon omarchy.launcher "{}" >/dev/null 2>&1
wait_for_layer "$NS" 10 || true
assert_layer "$NS" "summon maps the launcher layer"
screenshot "${TEST_NAME}-open"
omarchy-shell shell hide omarchy.launcher >/dev/null 2>&1
if wait_for_layer_gone "$NS" 10; then
  pass "hide unmaps the launcher layer"
else
  _fail_with_artifacts "hide unmaps the launcher layer"
fi
