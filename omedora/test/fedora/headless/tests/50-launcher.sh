#!/bin/bash
#
# L4-headless GOLDEN-IMAGE test — the walker app launcher (Super+Space).
#
# What it guards:
#   The SUPER+SPACE bind (default/hypr/bindings/utilities.lua:
#   `o.bind("SUPER + SPACE", "Launch apps", { omarchy = "walker" })`) resolves
#   to `omarchy-launch-walker` (no --dmenu) — the plain application launcher:
#   walker's default module list (apps/runner) rendered as a layer-surface
#   (gtk4-layer-shell). This test triggers that launcher the way the bind does,
#   waits for the `walker` layer to map, screenshots the live output, and diffs
#   it against a committed golden baseline.
#
# GOLDEN-IMAGE testing (read this before you touch the threshold):
#   The launcher is HIGH-ENTROPY — the list of installed apps it shows changes
#   across upstream versions and image contents. That is ACCEPTED here on one
#   explicit condition: the baseline is AFFIRMATIVELY REGENERATED when a rebase
#   onto a new upstream version legitimately changes the launcher. So this is a
#   golden-image gate, NOT a bulletproof pixel diff: it is tuned to catch
#   STRUCTURAL regressions (launcher didn't open / blank surface / walker not
#   rendering at all) while tolerating llvmpipe software-render noise. When the
#   launcher legitimately changes, this test goes red ON PURPOSE, a human
#   eyeballs artifacts/50-launcher/, confirms it's intended, and regenerates the
#   baseline (procedure below + in omedora/testing.md).
#
# THRESHOLD: 25% of pixels may differ.
#   Rationale: the launcher is a panel on an otherwise-static desktop (waybar +
#   wallpaper). When it renders, two captures of the same good session differ
#   only by llvmpipe AA noise + the masked search-field cursor — under a percent.
#   When it DOESN'T render (blank/black panel or no walker layer) the panel
#   region diverges hard and the diff blows past 25%. 25% is deliberately lenient
#   so the legitimate churn of the installed-app list across versions does NOT go
#   red, yet a structurally-absent launcher still fails (verified: no-launcher
#   capture vs a launcher baseline diffs far above 25%). Tighten only if you also
#   commit to regenerating the baseline on every app-list change.
#
# EXCLUSION ZONES (x,y,w,h logical px; masked to black in ref AND candidate):
#   The launcher walker surface is a centered panel on the 1920x1080 output. Its
#   "Search…" search field carries a blinking text cursor — genuinely
#   nondeterministic frame to frame — so we mask that one search-field row
#   (360,180,1000,70, located by cropping the committed baseline; it stays well
#   inside the panel, which spans x~310..1610 at this row). Per the maintainer we
#   lean on the THRESHOLD for the rest of the content variance rather than
#   masking every app row.
#
# REGENERATING THE BASELINE (fixtures/50-launcher-reference.png) — the point:
#   Do this when (and only when) a rebase legitimately changes the launcher and
#   this test goes red. Steps:
#     1. EYEBALL THE FAILURE. Look at
#        artifacts/50-launcher/50-launcher-candidate.png and
#        50-launcher-diff.png from the failed run. Confirm the launcher actually
#        rendered and the change is the expected upstream/app-list change (NOT a
#        blank/black panel — that's a real regression, do NOT regenerate).
#     2. CAPTURE A NEW BASELINE from a known-good session:
#          omedora/test/fedora/headless/run-tests.sh --keep --test '50-*'
#          podman exec <ctr> machinectl shell omedora@.host
#          # in-session: open the launcher and confirm the walker layer is up:
#          source ~/.local/share/omarchy/omedora/test/fedora/headless/lib.sh
#          headless_session_env
#          setsid uwsm-app -- omarchy-launch-walker >/dev/null 2>&1 &
#          wait_for_layer walker 10 && hyprctl layers | grep -q walker && \
#            grim ~/50-launcher-reference.png
#          # copy it out and commit it:
#          podman cp <ctr>:/home/omedora/50-launcher-reference.png \
#            omedora/test/fedora/headless/fixtures/50-launcher-reference.png
#     3. COMMIT the new baseline with a message noting the upstream version it
#        was regenerated for. Re-run '50-*' to confirm green.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

REFERENCE="$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/50-launcher-reference.png"

# Dynamic exclusion zones — see the header. The launcher panel is centered on
# the 1920x1080 output; mask the search-field row (blinking text cursor).
EXCLUSIONS=(
  "360,180,1000,70"   # "Search…" search-field row: blinking text cursor is nondeterministic
)

# Trigger the launcher exactly the way the SUPER+SPACE bind does: run
# `omarchy-launch-walker` (no --dmenu → the app launcher). Detached via
# setsid uwsm-app so it survives this shell and joins the session the same way
# the keybind's `exec` does.
setsid uwsm-app -- omarchy-launch-walker >/dev/null 2>&1 &
launcher_pid=$!

# Wait for the walker layer to map before screenshotting.
if ! wait_for_layer walker 10; then
  walker --close >/dev/null 2>&1 || true
  kill "$launcher_pid" >/dev/null 2>&1 || true
  wait "$launcher_pid" 2>/dev/null || true
  _fail_with_artifacts "walker launcher (Super+Space) maps a walker layer"
  exit 1
fi
# Let the surface finish painting its rows before we judge it.
sleep 1

assert_screenshot_matches "$REFERENCE" 25 \
  "walker launcher (Super+Space) renders (matches golden baseline within tolerance)" \
  "${EXCLUSIONS[@]}"

# Clean up: dismiss the launcher so it doesn't leak into later tests. Idempotent.
walker --close >/dev/null 2>&1 || true
kill "$launcher_pid" >/dev/null 2>&1 || true
wait "$launcher_pid" 2>/dev/null || true
for _ in $(seq 1 15); do
  hyprctl layers -j 2>/dev/null | grep -q '"namespace": "walker"' || break
  sleep 0.2
done
