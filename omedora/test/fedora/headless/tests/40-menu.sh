#!/bin/bash
#
# L4-headless GOLDEN-IMAGE test — the omarchy control menu (Super+Alt+Space).
#
# What it guards:
#   The SUPER+ALT+SPACE bind (default/hypr/bindings/utilities.lua:
#   `o.bind_menu("SUPER + ALT + SPACE", "Omarchy menu", nil)` →
#   `omarchy-menu`) opens the top-level omarchy control menu. `omarchy-menu`
#   with no arg calls show_main_menu, which pipes its option list into
#   `omarchy-launch-walker --dmenu` — i.e. the menu is a walker layer-surface
#   (gtk4-layer-shell), exactly like 10-walker. This test triggers that menu the
#   way the bind does, waits for the `walker` layer to map, screenshots the live
#   output, and diffs it against a committed golden baseline.
#
# GOLDEN-IMAGE testing (read this before you touch the threshold):
#   The omarchy menu is HIGH-ENTROPY — its option list changes across upstream
#   versions (entries added/removed/reworded). That is ACCEPTED here on one
#   explicit condition: the baseline is AFFIRMATIVELY REGENERATED when a rebase
#   onto a new upstream version legitimately changes the menu. So this is a
#   golden-image gate, NOT a bulletproof pixel diff: it is tuned to catch
#   STRUCTURAL regressions (menu didn't open / blank surface / wrong menu /
#   walker not rendering at all) while tolerating llvmpipe software-render noise.
#   When upstream legitimately changes the menu, this test goes red ON PURPOSE,
#   a human eyeballs artifacts/40-menu/, confirms the change is intended, and
#   regenerates the baseline (procedure below + in omedora/testing.md).
#
# THRESHOLD: 25% of pixels may differ.
#   Rationale: the menu surface is a small panel on an otherwise-static desktop
#   (waybar + wallpaper). When the menu renders, two captures of the same good
#   session differ only by llvmpipe AA noise + the masked search-field cursor —
#   well under a percent. When the menu DOESN'T render (blank/black panel, wrong
#   menu, or no walker layer) the panel region diverges hard and the diff blows
#   past 25%. 25% is deliberately lenient: it absorbs the legitimate row-by-row
#   churn of the menu's option text across upstream versions WITHOUT going red,
#   yet a structurally-absent menu still fails (verified: no-menu capture vs a
#   menu baseline diffs far above 25%). Tighten only if you also commit to
#   regenerating the baseline on every upstream menu wording change.
#
# EXCLUSION ZONES (x,y,w,h logical px; masked to black in ref AND candidate):
#   The omarchy menu walker surface is a left-of-center panel on the 1920x1080
#   output. Its "Go…" search field carries a blinking text cursor — genuinely
#   nondeterministic frame to frame — so we mask that one search-field row
#   (690,55,320,65, located by cropping the committed baseline). Per the
#   maintainer we lean on the THRESHOLD for the rest of the content variance
#   rather than masking every menu row.
#
# REGENERATING THE BASELINE (fixtures/40-menu-reference.png) — the whole point:
#   Do this when (and only when) a rebase legitimately changes the menu and this
#   test goes red. Steps:
#     1. EYEBALL THE FAILURE. Look at artifacts/40-menu/40-menu-candidate.png
#        and 40-menu-diff.png from the failed run. Confirm the menu actually
#        rendered and the change is the expected upstream menu change (NOT a
#        blank/black panel — that's a real regression, do NOT regenerate).
#     2. CAPTURE A NEW BASELINE from a known-good session:
#          omedora/test/fedora/headless/run-tests.sh --keep --test '40-*'
#          podman exec <ctr> machinectl shell omedora@.host
#          # in-session: open the menu and confirm the walker layer is present:
#          source ~/.local/share/omarchy/omedora/test/fedora/headless/lib.sh
#          headless_session_env
#          setsid uwsm-app -- omarchy-menu >/dev/null 2>&1 &
#          wait_for_layer walker 10 && hyprctl layers | grep -q walker && \
#            grim ~/40-menu-reference.png
#          # copy it out and commit it:
#          podman cp <ctr>:/home/omedora/40-menu-reference.png \
#            omedora/test/fedora/headless/fixtures/40-menu-reference.png
#     3. COMMIT the new baseline with a message noting the upstream version it
#        was regenerated for. Re-run '40-*' to confirm green.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

REFERENCE="$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/40-menu-reference.png"

# Dynamic exclusion zones — see the header. The menu panel is centered on the
# 1920x1080 output; mask the search-field row (blinking text cursor).
EXCLUSIONS=(
  "690,55,320,65"   # "Go…" search-field row: blinking text cursor is nondeterministic
  "840,52,1080,68"  # Hyprland 0.56.1 per-login ".conf goes away in 0.57" banner:
                    # compositor-drawn (makoctl cannot dismiss it), right-aligned
                    # under the waybar. Accepted + documented behavior
                    # (omedora/install.md §6), so it must not fail the gate.
)

# Trigger the menu exactly the way the SUPER+ALT+SPACE bind does: run
# `omarchy-menu` (no arg → show_main_menu → omarchy-launch-walker --dmenu).
# Detached via setsid uwsm-app so it survives this shell and joins the session
# the same way the keybind's `exec` does.
setsid uwsm-app -- omarchy-menu >/dev/null 2>&1 &
menu_pid=$!

# Wait for the walker layer to map before screenshotting.
if ! wait_for_layer walker 10; then
  walker --close >/dev/null 2>&1 || true
  kill "$menu_pid" >/dev/null 2>&1 || true
  wait "$menu_pid" 2>/dev/null || true
  _fail_with_artifacts "omarchy menu (Super+Alt+Space) maps a walker layer"
  exit 1
fi
# Let the surface finish painting its rows before we judge it.
sleep 1

assert_screenshot_matches "$REFERENCE" 25 \
  "omarchy menu (Super+Alt+Space) renders (matches golden baseline within tolerance)" \
  "${EXCLUSIONS[@]}"

# Clean up: dismiss the menu so it doesn't leak into later tests. Idempotent.
walker --close >/dev/null 2>&1 || true
kill "$menu_pid" >/dev/null 2>&1 || true
wait "$menu_pid" 2>/dev/null || true
for _ in $(seq 1 15); do
  hyprctl layers -j 2>/dev/null | grep -q '"namespace": "walker"' || break
  sleep 0.2
done
