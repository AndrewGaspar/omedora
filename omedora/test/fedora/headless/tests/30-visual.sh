#!/bin/bash
#
# L4-headless VISUAL acceptance test — the v4 session must LOOK right.
#
# Why this exists (the whole point):
#   00-session.sh asserts the shell is alive and its layers are REGISTERED
#   (quickshell proc, shell ping, omarchy-bar/omarchy-background in hyprctl
#   layers). But a layer can be mapped and still paint garbage: a broken QML
#   bar, a black/fallback wallpaper, a theme regression. This test closes that
#   gap: it captures the live output with grim and diffs it against a
#   committed known-good reference, so a blank bar or a missing wallpaper
#   makes the diff blow past threshold and the test reports `not ok`.
#
# How it works:
#   - grim the whole headless output (fixed 1920x1080 — the launcher's headless
#     monitor; grim emits logical pixels).
#   - Mask the dynamic regions (below) to solid black in BOTH the candidate and
#     the reference, then ImageMagick `compare -metric AE -fuzz` them. The
#     normalized differing-pixel fraction must be <= THRESHOLD. We use a
#     tolerance (not pixel-perfect): we only care about the coarse signal "are
#     the big static structures (bar band + wallpaper) drawn?". A missing bar
#     band or a black wallpaper moves the diff from ~0% to tens of percent.
#
# DYNAMIC EXCLUSION ZONES (x,y,w,h in logical px; masked in ref AND candidate).
# The headless output is 1920x1080 at scale 1 (monitors.lua scale "auto"
# resolves to 1 on this output). The v4 bar (shell/plugins/bar) is the top
# band; the shell sizes it from the font/scale — measured ~51px tall on this
# output (rows 0..50 are the solid bar band, row 52+ is wallpaper). Its default
# layout (config/omarchy/shell.json) clusters the time/state-dependent content
# left / center / right, and each cluster below masks the FULL band height
# (52px) so glyph ascenders/descenders are covered even as the clock rolls over:
#
#   0,0,420,52      LEFT cluster: omarchy.menu glyph + omarchy.workspaces.
#                   The focused-workspace pill and which workspaces exist are
#                   STATE-dependent. Excluded.
#   700,0,520,52    CENTER cluster: omarchy.clock ("dddd HH:mm" — changes every
#                   minute) + weather / system-update / indicators. Excluded.
#   1500,0,420,52   RIGHT cluster: tray + bluetooth + network + audio + the
#                   battery/cpu tail. All state-dependent. Excluded.
#
# What's left UNMASKED and therefore actually asserted:
#   - the bar's solid background band across the rest of the top ~51px (proves
#     the bar is DRAWN — if it's missing, these rows show wallpaper/black), and
#   - the entire wallpaper region (rows 52..1079) — proves the shell's
#     background service painted the real theme wallpaper, not a black fill.
#
# THRESHOLD: 1.0% of pixels may differ. Empirically (v4 shell, GPU-rendered):
# two captures of the same good session diff at ~0%; a missing bar diffs at
# >2%, a black wallpaper at tens of percent. 1% sits in the wide gap.
#
# REGENERATING THE REFERENCE (fixtures/30-visual-reference.png):
#   Do this when the UI legitimately changes (bar layout/height, default
#   wallpaper/theme) and this test goes red on an EYEBALLED-good candidate:
#     1. Look at artifacts/30-visual/30-visual-candidate.png + the -diff.png.
#        Confirm bar + wallpaper truly rendered (a blank band/black wallpaper
#        is a real regression — do NOT regenerate).
#     2. From a known-good session:
#          omedora/test/fedora/headless/run-tests.sh --keep --test '30-*'
#          podman exec -it <ctr> machinectl shell omedora@.host
#          # in-session:
#          source ~/headless-suite/lib.sh && headless_session_env
#          omarchy-shell -q notifications dismissAll; sleep 2
#          grim /home/omedora/30-visual-reference.png
#          # from the host:
#          podman cp <ctr>:/home/omedora/30-visual-reference.png \
#            omedora/test/fedora/headless/fixtures/30-visual-reference.png
#     3. Re-run '30-*' TWICE to prove the new golden is stable, then commit it
#        noting the change it was regenerated for, and re-check the exclusion
#        rectangles still cover all dynamic clusters.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

REFERENCE="$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/30-visual-reference.png"

# Dynamic exclusion zones — see the header for what/why of each.
EXCLUSIONS=(
  "0,0,420,52"      # left: menu glyph + workspaces (focused pill is state-dependent)
  "700,0,520,52"    # center: clock (changes every minute) + weather/update/indicators
  "1500,0,420,52"   # right: tray + bluetooth/network/audio tail (state-dependent)
)

# The bar + background layers can come up slightly after Hyprland IPC; give the
# shell a moment to render before we judge it (this test catches a PERMANENT
# miss, not a startup transient).
wait_for_shell_ping 30 || true
wait_for_layer omarchy-bar 15 || true
wait_for_layer omarchy-background 15 || true

# Dismiss the IDLE SCREENSAVER if it fired. The session's idle hook launches a
# fullscreen TTE screensaver (foot --app-id=org.omarchy.screensaver) after a few
# minutes of no input; in a long-lived/--keep container the suite can reach this
# test after that timeout, and the screensaver covers the whole output (a ~96%
# diff that is NOT a wallpaper regression). Kill it + nudge the cursor to reset
# the idle timer so we capture the real static desktop, not the screensaver.
# (The background layer keeps its buffer underneath — Fedora 44's quickshell
# never parks window updates — so the wallpaper is intact once it's uncovered.)
pkill -f omarchy-screensaver >/dev/null 2>&1 || true
hyprctl dispatch movecursor 100 540 >/dev/null 2>&1 || true
hyprctl dispatch movecursor 960 540 >/dev/null 2>&1 || true
wait_for_layer_gone org.omarchy.screensaver 5 >/dev/null 2>&1 || true

# Clear any first-run notifications before capturing. They fire once at
# session start and linger as a toast stack over the wallpaper — which this
# test diffs. The committed reference is captured after a dismissAll (see the
# regenerate procedure above), so the candidate must match: dismiss, then let
# the notification layer tear down before grim.
omarchy-shell -q notifications dismissAll >/dev/null 2>&1 || true
sleep 2

assert_screenshot_matches "$REFERENCE" 1.0 \
  "session renders the shell bar + wallpaper (matches reference within tolerance)" \
  "${EXCLUSIONS[@]}"
