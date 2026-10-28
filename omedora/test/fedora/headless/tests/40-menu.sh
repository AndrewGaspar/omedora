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
# Then a package-gated row: with voxtype installed through omarchy-pkg-add
# (voxtype-bin -> the voxtype RPM), Remove > Dictation must list Voxtype and
# never the skip-mapped Superwhisper. The menu answers such guards in one
# batch that upstream builds from pacman; on Fedora that hid every Remove row
# until the batch learned to ask bin/fedora/pkg.py. Read off the screen with
# tesseract, as upstream's acceptance tests do.
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

# 5. A package-gated row follows the Fedora package map.
menu_text() {
  local shot="$ARTIFACTS/${TEST_NAME}-ocr.png"
  grim -s 2 "$shot" >/dev/null 2>&1 || return 1
  tesseract "$shot" stdout --psm 11 2>/dev/null
}

# Opens Remove > Dictation and waits (guards land asynchronously) until the
# screen does (want=1) or does not (want=0) show "Voxtype".
dictation_shows_voxtype() {
  local want="$1" text=""
  omarchy-menu summon remove.dictation >/dev/null 2>&1
  wait_for_layer "$NS" 10 || return 1
  for _ in {1..10}; do
    sleep 1
    text=$(menu_text) || continue
    if grep -qi "voxtype" <<<"$text"; then (( want == 1 )) && break; else (( want == 0 )) && break; fi
  done
  printf '%s\n' "$text" >"$ARTIFACTS/${TEST_NAME}-remove-dictation-$want.txt"
  screenshot "${TEST_NAME}-remove-dictation-$want"
  omarchy-menu close >/dev/null 2>&1
  wait_for_layer_gone "$NS" 10 || true
  local shown=0
  grep -qi "voxtype" <<<"$text" && shown=1
  (( shown == want ))
}

if ! command -v tesseract >/dev/null || ! command -v grim >/dev/null; then
  _fail_with_artifacts "tesseract and grim are present to read the menu (both are base packages)"
fi

voxtype_was_installed=false
rpm -q voxtype >/dev/null 2>&1 && voxtype_was_installed=true
if ! $voxtype_was_installed; then
  if dictation_shows_voxtype 0; then
    pass "Remove > Dictation lists no Voxtype while voxtype is not installed"
  else
    _fail_with_artifacts "Remove > Dictation lists no Voxtype while voxtype is not installed"
  fi
  omarchy-pkg-add voxtype-bin >"$ARTIFACTS/${TEST_NAME}-pkg-add.log" 2>&1 ||
    _fail_with_artifacts "omarchy-pkg-add voxtype-bin installs the voxtype RPM"
fi
rpm -q voxtype >/dev/null 2>&1 || _fail_with_artifacts "voxtype-bin resolves to the voxtype RPM"

if dictation_shows_voxtype 1; then
  pass "Remove > Dictation lists Voxtype once voxtype is installed (guard answered through pkg.py)"
else
  _fail_with_artifacts "Remove > Dictation lists Voxtype once voxtype is installed (guard answered through pkg.py)"
fi
if grep -qi "superwhisper" "$ARTIFACTS/${TEST_NAME}-remove-dictation-1.txt"; then
  _fail_with_artifacts "Remove > Dictation never lists the skip-mapped Superwhisper"
else
  pass "Remove > Dictation never lists the skip-mapped Superwhisper"
fi

$voxtype_was_installed || sudo dnf remove -y voxtype >/dev/null 2>&1 || true
