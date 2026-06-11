#!/bin/bash
#
# L4-headless acceptance test for the walker menu (#56).
#
# `omarchy-menu` (Super+Alt+Space) pipes its options into
# `omarchy-launch-walker --dmenu`; that dmenu invocation is exactly what every
# menu prompt renders through. This test drives that path directly and asserts a
# `walker` layer-surface appears in `hyprctl layers`.
#
# Because #56 was FLAKY (the forwarded-to-daemon render painted no layer in this
# software-rendered nested container, intermittently), a single open is not a
# trustworthy signal. So we open the menu ITERS times, count how many produced a
# walker layer, and report the success rate. The suite passes only if EVERY open
# rendered (rate == ITERS/ITERS) — that's the regression guard that turns "flaky"
# into a hard gate.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

ITERS="${WALKER_TEST_ITERS:-20}"

# Open the menu once: feed options into the same dmenu path omarchy-menu uses,
# detached, wait briefly for the walker layer, capture the result, then close.
# Returns 0 if the walker layer appeared, 1 otherwise.
open_menu_once() {
  # Feed a few options the way omarchy-menu does; --dmenu reads them on stdin.
  printf '%s\n' "Alpha" "Bravo" "Charlie" \
    | omarchy-launch-walker --dmenu -p "test…" >/dev/null 2>&1 &
  local walker_pid=$!

  local seen=1
  if wait_for_layer walker 5; then
    seen=0
  fi

  # Close walker (omarchy-menu's own toggle uses `walker --close`) and reap.
  walker --close >/dev/null 2>&1 || true
  kill "$walker_pid" >/dev/null 2>&1 || true
  wait "$walker_pid" 2>/dev/null || true
  # Let the layer tear down before the next iteration so counts don't overlap.
  for _ in $(seq 1 15); do
    hyprctl layers -j 2>/dev/null | grep -q '"namespace": "walker"' || break
    sleep 0.2
  done
  return $seen
}

ok=0
for i in $(seq 1 "$ITERS"); do
  if open_menu_once; then
    ok=$((ok + 1))
  else
    # Capture artifacts from the first failure for debugging.
    [[ $ok -eq $((i - 1)) ]] && { screenshot "${TEST_NAME}-miss-$i"; dump_state "${TEST_NAME}-miss-$i"; }
  fi
done

printf '# walker render rate: %d/%d opens produced a layer\n' "$ok" "$ITERS"

# Hard gate: every single open must render the walker layer.
assert_equals "walker menu renders on every open ($ok/$ITERS)" "$ok" "$ITERS"
