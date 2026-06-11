#!/bin/bash
#
# L4-headless VISUAL acceptance test — the session must LOOK right.
#
# Why this exists (the whole point):
#   00-session.sh asserts the autostart *processes* are running
#   (assert_proc waybar/swaybg/mako). But a process can be alive and NOT
#   visually present: a uwsm app-daemon autostart race has been observed to
#   drop waybar + swaybg from actually RENDERING while the processes
#   (sometimes) still exist — leaving a black screen with no bar and no
#   wallpaper that the process-based test happily passes. This test closes
#   that gap: it captures the live output with grim and diffs it against a
#   committed known-good reference, so a missing/blank waybar or a
#   black/fallback wallpaper makes the diff blow past threshold and the test
#   reports `not ok`.
#
# How it works:
#   - grim the whole headless output (fixed 1920x1080 — the launcher's headless
#     monitor; grim emits logical pixels).
#   - Mask the dynamic regions (below) to solid black in BOTH the candidate and
#     the reference, then ImageMagick `compare -metric AE -fuzz` them. The
#     normalized differing-pixel fraction must be <= THRESHOLD_PCT. We use a
#     tolerance (not pixel-perfect): the session renders via llvmpipe, and we
#     only care about the coarse signal "are the big static structures drawn?"
#     A missing waybar band or a black wallpaper moves the diff from ~0% to
#     tens of percent — far above threshold.
#
# DYNAMIC EXCLUSION ZONES (x,y,w,h in logical px; masked in ref AND candidate).
# The headless output is 1920x1080. The waybar band is the top 52px
# (config height 26 * monitor scale 2.0). Each rectangle below is a cluster of
# time/state-dependent waybar content found from the REAL omedora waybar layout
# (config/waybar/config.jsonc) by scanning the captured band; we mask the whole
# 52px band height per cluster so icon ascenders/descenders are covered:
#
#   20,0,272,52    LEFT cluster: custom/omarchy menu glyph + hyprland/workspaces.
#                  The active-workspace marker (󱓻) and which workspaces are
#                  occupied are STATE-dependent, so the whole left group is
#                  excluded.
#   825,0,285,52   CENTER cluster: clock#horizontal ("{:L%A %H:%M}") plus the
#                  weather / update-available / screen-recording / idle /
#                  notification-silencing indicators. Clock changes every
#                  minute; indicators are state-dependent. Excluded.
#   1645,0,260,52  RIGHT cluster: tray + bluetooth + network + pulseaudio + cpu
#                  + battery. Network/battery/bluetooth icons and the tray are
#                  state-dependent. Excluded.
#
# What's left UNMASKED and therefore actually asserted:
#   - the solid waybar background band across the rest of the top 52px (proves
#     waybar is DRAWN — if it's missing, these rows show wallpaper/black), and
#   - the entire wallpaper region (rows 52..1079) — proves swaybg painted the
#     real background, not a solid-black fallback.
#
# THRESHOLD: 1.0% of pixels may differ. Empirically: two captures of the same
# good session diff at 0.0%; a missing waybar diffs at ~2.8%, a black wallpaper
# at ~95%, a fully-broken (no bar + no wallpaper) session at ~98%. 1% sits in
# the wide gap and is robust to llvmpipe/theme noise.
#
# REGENERATING THE REFERENCE (omedora/test/fedora/headless/fixtures/30-visual-reference.png):
#   Boot a session with `run-tests.sh --keep`, attach as omedora, and CONFIRM
#   the components are truly up (autostart race can drop them) — the `wallpaper`
#   and `waybar` layers must both appear in `hyprctl layers`. If they're
#   missing, relaunch them as persistent user units before capturing, e.g.:
#     systemd-run --user --unit=ref-swaybg --setenv=WAYLAND_DISPLAY=$WL \
#       swaybg -i ~/.config/omarchy/current/background -m fill
#     systemd-run --user --unit=ref-waybar --setenv=WAYLAND_DISPLAY=$WL waybar
#   then `makoctl dismiss --all` (clear transient notifications) and
#   `grim fixtures/30-visual-reference.png`. The dynamic content (clock, etc.)
#   in the reference is irrelevant because it's masked; regenerate only when the
#   UI legitimately changes (waybar height, wallpaper, static layout) — and
#   re-check the exclusion rectangles still cover all dynamic clusters.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

REFERENCE="$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/30-visual-reference.png"

# Dynamic exclusion zones — see the header for what/why of each.
EXCLUSIONS=(
  "20,0,272,52"     # left: omarchy menu glyph + workspaces (active-ws marker is state-dependent)
  "825,0,285,52"    # center: clock (changes every minute) + weather/update/recording/idle indicators
  "1645,0,260,52"   # right: tray + bluetooth/network/pulseaudio/cpu/battery (state-dependent)
)

# The waybar + wallpaper layers can come up slightly after Hyprland IPC; give
# the autostart chain a moment to render before we judge it (this test catches
# a PERMANENT miss, not a startup transient).
wait_for_layer waybar 10 || true
wait_for_layer wallpaper 10 || true

# Clear the first-run welcome notifications ("Setup Wi-Fi", "Update System",
# "Learn Keybindings") before capturing. They fire once at session start and
# linger as a mako stack over the RIGHT side of the wallpaper — which this test
# diffs — pushing an otherwise-perfect session to ~16% and a false `not ok`.
# The committed reference is captured after `makoctl dismiss --all` (see the
# regenerate procedure above), so the candidate must match: dismiss, then let
# the notification layer tear down before grim.
command -v makoctl >/dev/null && makoctl dismiss --all >/dev/null 2>&1 || true
sleep 1

assert_screenshot_matches "$REFERENCE" 1.0 \
  "session renders waybar + wallpaper (matches reference within tolerance)" \
  "${EXCLUSIONS[@]}"
