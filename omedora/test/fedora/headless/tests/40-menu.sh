#!/bin/bash
#
# L4-headless acceptance test for the v4 Omarchy menu (Super+Alt+Space).
#
# The SUPER+ALT+SPACE bind (default/hypr/bindings/utilities.lua:
#   o.bind("SUPER + ALT + SPACE", "Omarchy menu", "omarchy-menu toggle root")
# ) opens the top-level Omarchy control menu — on the v4 line a Quickshell
# plugin (`omarchy.menu`, shell/plugins/menu/Menu.qml, layer namespace
# `omarchy-menu`) driven through the thin `omarchy-menu` IPC wrapper. This test
# drives the exact bind command and asserts the menu layer maps; then closes it
# via `omarchy-menu close` and asserts it unmaps. A couple of route summons
# (system) prove routing works, and `omarchy-menu ping` proves the plugin's
# call surface answers.
#
# This replaces the 3.8.2-era golden-image 40-menu.sh: the walker-rendered
# menu panel is gone, and the structural signal we actually gated on — "the
# menu opens, renders a surface, and closes" — is asserted directly via
# layer-surface presence, with a screenshot kept as a debugging artifact
# rather than a golden (30-visual owns the pixel-level gate for the static
# desktop).
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

NS=omarchy-menu

# Always close the menu on the way out so it can't leak into later tests.
cleanup() {
  omarchy-menu close >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for_shell_ping 30 || true
assert_shell_ping "shell answers ping before driving the menu"

# 1. The bind's exact command opens the root menu.
omarchy-menu toggle root >/dev/null 2>&1
if wait_for_layer "$NS" 10; then
  pass "omarchy-menu toggle root maps the menu layer"
else
  _fail_with_artifacts "omarchy-menu toggle root maps the menu layer"
fi
sleep 1   # let the panel finish painting before the artifact screenshot
screenshot "${TEST_NAME}-root"

# 2. The plugin's call surface answers once loaded.
ping_out=$(omarchy-menu ping 2>/dev/null)
assert_output_contains "omarchy-menu ping answers" "${ping_out:-<none>}" "ok"

# 3. Close unmaps it.
omarchy-menu close >/dev/null 2>&1
if wait_for_layer_gone "$NS" 10; then
  pass "omarchy-menu close unmaps the menu layer"
else
  _fail_with_artifacts "omarchy-menu close unmaps the menu layer"
fi

# 4. Routes resolve: summon a non-root route (the system menu — the
# SUPER+ESCAPE bind) and confirm the layer maps again.
omarchy-menu summon system >/dev/null 2>&1
if wait_for_layer "$NS" 10; then
  pass "omarchy-menu summon system maps the menu layer"
else
  _fail_with_artifacts "omarchy-menu summon system maps the menu layer"
fi
screenshot "${TEST_NAME}-system"
omarchy-menu close >/dev/null 2>&1
wait_for_layer_gone "$NS" 10 || true
