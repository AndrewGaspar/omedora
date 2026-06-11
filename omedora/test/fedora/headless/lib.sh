#!/bin/bash
#
# In-container helper library for the L4-headless automated test suite.
#
# Every test under omedora/test/fedora/headless/tests/ sources THIS file as its first
# line, then calls `headless_session_env` to attach to the live nested Hyprland
# session. It builds on the shared TAP primitives in test/helpers.sh (pass,
# fail, assert_output_contains, assert_equals, ...) so L1 and L4 tests speak the
# same language, and adds session-aware assertions (layers, clients, monitors,
# procs) plus artifact capture (grim screenshots, hyprctl dumps).
#
# Runs AS the omedora user INSIDE the container's logind session (entered via
# `machinectl shell` by run-tests.sh). The host orchestrator copies this file +
# the tests/ dir into the container and runs each test there.
#
# Convention for a test (omedora/test/fedora/headless/tests/NN-name.sh):
#   #!/bin/bash
#   source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
#   headless_session_env
#   # ... drive the session (hyprctl dispatch exec ...), then assert:
#   wait_for_layer walker 5
#   assert_layer walker "omarchy-menu renders a walker surface"
# Each assertion emits a TAP line via pass/fail. A failure auto-screenshots +
# dumps state to $ARTIFACTS and exits non-zero (helpers.sh `fail` does the exit),
# so the orchestrator sees a non-zero exit and copies artifacts out.

# --- locate the in-container omarchy tree + shared TAP helpers ----------------
# In the session image the omarchy tree lives at ~/.local/share/omarchy.
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
_HELPERS="$OMARCHY_PATH/test/helpers.sh"
if [[ ! -f $_HELPERS ]]; then
  # Fall back to a path relative to this file (e.g. running from a checkout).
  # This file lives at omedora/test/fedora/headless/lib.sh; the upstream TAP
  # helpers stay at the repo-root test/helpers.sh (four levels up).
  _HELPERS="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)/test/helpers.sh"
fi
# shellcheck source=/dev/null
. "$_HELPERS"

# --- artifacts ----------------------------------------------------------------
# Each test writes screenshots / state dumps here. run-tests.sh sets ARTIFACTS
# to a per-test dir inside the container and copies it out on failure; if unset
# (e.g. a test run by hand inside the session) we default to a tmp dir.
ARTIFACTS="${ARTIFACTS:-/tmp/headless-artifacts}"
mkdir -p "$ARTIFACTS" 2>/dev/null || true

# Test name (for artifact filenames); derived from $0 if not set by the runner.
TEST_NAME="${TEST_NAME:-$(basename -- "${0%.sh}")}"

# --- session env --------------------------------------------------------------
# Attach this shell to the running nested Hyprland session:
#   - HYPRLAND_INSTANCE_SIGNATURE from $XDG_RUNTIME_DIR/hypr (the live instance)
#   - WAYLAND_DISPLAY from `hyprctl instances` (the nested compositor socket)
#   - source ~/.config/uwsm/env so omarchy-* / walker / grim are on PATH
# Idempotent: safe to call once per test.
headless_session_env() {
  : "${XDG_RUNTIME_DIR:?need XDG_RUNTIME_DIR (run via machinectl shell as omedora)}"

  # PATH + session env (omarchy bin dir, GSK_RENDERER, etc.). uwsm/env is what
  # the session launcher sourced; sourcing it here gives the test the same PATH.
  [[ -f "$HOME/.config/uwsm/env" ]] && source "$HOME/.config/uwsm/env"
  export GSK_RENDERER="${GSK_RENDERER:-cairo}"

  local sig
  sig=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
  [[ -n $sig ]] || { echo "no Hyprland instance under $XDG_RUNTIME_DIR/hypr (session not up?)" >&2; exit 3; }
  export HYPRLAND_INSTANCE_SIGNATURE="$sig"

  local wl
  wl=$(hyprctl instances -j 2>/dev/null | python3 -c \
    'import sys,json;d=json.load(sys.stdin);print(d[0]["wl_socket"]) if d else print("")' 2>/dev/null)
  [[ -n $wl ]] && export WAYLAND_DISPLAY="$wl"
}

# --- artifact capture ---------------------------------------------------------

# screenshot <name> — grim the whole output to $ARTIFACTS/<name>.png.
screenshot() {
  local name="$1"
  command -v grim >/dev/null || return 0
  grim "$ARTIFACTS/${name}.png" >/dev/null 2>&1 || true
}

# assert_screenshot_matches <reference.png> <threshold-pct> [desc] [exclusions...]
# ---------------------------------------------------------------------------
# Tolerance-based screenshot-diff assertion: grab the live output with grim,
# mask the same dynamic rectangles in BOTH the candidate and the committed
# reference, then compare. Emits ONE TAP line (pass/fail) and, on failure,
# saves the candidate + a visual diff to $ARTIFACTS for inspection.
#
# Why a diff (not a pixel-perfect compare): the headless session renders via
# llvmpipe (software). In practice two captures of the same good session are
# byte-identical here, but we still diff with a fuzz + a percentage threshold
# so trivial AA / theme-noise never flakes the gate. The signal we actually
# want is coarse: "are the big static structures (the waybar band, the
# wallpaper) actually DRAWN?" — a missing waybar or a black/fallback wallpaper
# moves the differing-pixel fraction from ~0% to tens of percent, far above any
# sane threshold.
#
# Args:
#   reference      path to the committed reference PNG (same geometry as grim)
#   threshold-pct  max % of pixels allowed to differ (e.g. 1.0). The metric is
#                  ImageMagick `compare -metric AE -fuzz <FUZZ>` normalized by
#                  the pixel count; a per-pixel colour delta below FUZZ doesn't
#                  count as a difference.
#   desc           TAP description (optional)
#   exclusions     zero or more "x,y,w,h" rectangles (logical px) masked to
#                  solid black in BOTH images before diffing. These are the
#                  dynamic regions (clock, workspace marker, tray, ...). The
#                  CALLER documents what each rectangle is and why.
#
# Tunables via env (defaults are sane for the headless llvmpipe session):
#   SCREENSHOT_DIFF_FUZZ   per-pixel colour tolerance (default 5%)
assert_screenshot_matches() {
  local reference="$1"; local threshold="$2"; local desc="${3:-screenshot matches reference}"
  shift 3 || true
  local exclusions=("$@")
  local fuzz="${SCREENSHOT_DIFF_FUZZ:-5%}"

  if ! command -v grim >/dev/null || ! command -v magick >/dev/null; then
    _fail_with_artifacts "$desc (grim/magick missing in session)"
    return
  fi
  if [[ ! -f $reference ]]; then
    _fail_with_artifacts "$desc (reference not found: $reference)"
    return
  fi

  local tag="${TEST_NAME}"
  local cand="$ARTIFACTS/${tag}-candidate.png"
  local cand_m="$ARTIFACTS/${tag}-candidate-masked.png"
  local ref_m="$ARTIFACTS/${tag}-reference-masked.png"
  local diffimg="$ARTIFACTS/${tag}-diff.png"

  if ! grim "$cand" >/dev/null 2>&1; then
    _fail_with_artifacts "$desc (grim capture failed)"
    return
  fi

  # Reference and candidate must share geometry, or the diff is meaningless.
  local rgeom cgeom
  rgeom=$(magick identify -format '%wx%h' "$reference" 2>/dev/null)
  cgeom=$(magick identify -format '%wx%h' "$cand" 2>/dev/null)
  if [[ "$rgeom" != "$cgeom" ]]; then
    # The committed goldens are captured at the L4-headless output geometry
    # (1920x1080). The L4-VM tier renders at whatever mode the virtio-gpu
    # advertises (often 1280x800), so a pixel-diff against the headless golden
    # is meaningless there. SCREENSHOT_GEOMETRY_SKIP (set only by the VM runner)
    # downgrades a geometry mismatch to a TAP SKIP instead of a hard fail — the
    # VM tier proves the session RENDERS via the framebuffer screenshot + the
    # layer-presence assertions, just not against the resolution-specific golden.
    # UNSET by default, so the podman L4 tier stays strict.
    if [[ -n ${SCREENSHOT_GEOMETRY_SKIP:-} ]]; then
      pass "# SKIP $desc (golden geometry $rgeom != VM candidate $cgeom; rendering proven structurally)"
    else
      _fail_with_artifacts "$desc (geometry mismatch: ref=$rgeom candidate=$cgeom)"
    fi
    return
  fi

  # Build the mask draw-list shared by both images.
  local -a draw=()
  local rect x y w h
  for rect in "${exclusions[@]}"; do
    IFS=, read -r x y w h <<<"$rect"
    draw+=(-draw "rectangle $x,$y $((x + w - 1)),$((y + h - 1))")
  done

  magick "$cand"      -fill black "${draw[@]}" "$cand_m" 2>/dev/null
  magick "$reference" -fill black "${draw[@]}" "$ref_m"  2>/dev/null

  # compare -metric AE prints "<count> (<normalized-fraction>)"; the normalized
  # fraction is differing-pixels / total-pixels — exactly the % we threshold on.
  local out frac pct
  out=$(magick compare -metric AE -fuzz "$fuzz" "$ref_m" "$cand_m" "$diffimg" 2>&1) || true
  frac=$(printf '%s\n' "$out" | grep -oE '\(([0-9.eE+-]+)\)' | tr -d '()' | head -1)
  [[ -n $frac ]] || frac=1   # unparseable => treat as fully different
  pct=$(python3 -c "print(f'{float('$frac')*100:.4f}')" 2>/dev/null || echo 100)

  if python3 -c "import sys; sys.exit(0 if float('$frac')*100 <= float('$threshold') else 1)"; then
    pass "$desc (diff ${pct}% <= ${threshold}%)"
  else
    # Keep the candidate + diff visible even on failure (artifacts only copied
    # out by the runner on a non-zero exit, which fail triggers).
    _fail_with_artifacts "$desc (diff ${pct}% > ${threshold}% — component missing/blank?)"
  fi
}

# dump_state <name> — hyprctl layers/clients/monitors -j + failed user units.
dump_state() {
  local name="$1"
  hyprctl layers -j   >"$ARTIFACTS/${name}.layers.json"   2>/dev/null || true
  hyprctl clients -j  >"$ARTIFACTS/${name}.clients.json"  2>/dev/null || true
  hyprctl monitors -j >"$ARTIFACTS/${name}.monitors.json" 2>/dev/null || true
  systemctl --user list-units --failed --no-legend \
                      >"$ARTIFACTS/${name}.failed-units.txt" 2>/dev/null || true
}

# Internal: on any assertion failure capture a screenshot + state dump, then let
# helpers.sh `fail` print the TAP line and exit. Used by the assert_* wrappers.
_fail_with_artifacts() {
  local desc="$1"
  local tag="${TEST_NAME}-fail"
  screenshot "$tag"
  dump_state "$tag"
  fail "$desc"
}

# --- session assertions (each emits a TAP line) -------------------------------

# assert_layer <ns> [desc] — a layer-surface namespace is present in any layer
# level on any monitor (hyprctl layers).
assert_layer() {
  local ns="$1"; local desc="${2:-layer present: $ns}"
  if hyprctl layers -j 2>/dev/null | grep -q "\"namespace\": \"$ns\""; then
    pass "$desc"
  else
    _fail_with_artifacts "$desc"
  fi
}

# wait_for_layer <ns> <timeout-seconds> — poll until the layer appears or the
# timeout elapses. Does NOT emit a TAP line itself (it's a wait, not an assert);
# returns 0 if seen, 1 on timeout. Follow with assert_layer to record the result.
wait_for_layer() {
  local ns="$1"; local timeout="${2:-5}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    hyprctl layers -j 2>/dev/null | grep -q "\"namespace\": \"$ns\"" && return 0
    sleep 0.2
  done
  return 1
}

# assert_client <class> [desc] — a client window with the given class exists.
assert_client() {
  local class="$1"; local desc="${2:-client present: $class}"
  if hyprctl clients -j 2>/dev/null | grep -q "\"class\": \"$class\""; then
    pass "$desc"
  else
    _fail_with_artifacts "$desc"
  fi
}

# wait_for_client <class> <timeout-seconds> — poll for a client window.
wait_for_client() {
  local class="$1"; local timeout="${2:-5}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    hyprctl clients -j 2>/dev/null | grep -q "\"class\": \"$class\"" && return 0
    sleep 0.2
  done
  return 1
}

# assert_monitor [desc] — at least one Hyprland monitor exists.
assert_monitor() {
  local desc="${1:-at least one monitor}"
  local n
  n=$(hyprctl monitors -j 2>/dev/null | python3 -c \
    'import sys,json;print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  if [[ "$n" -ge 1 ]]; then
    pass "$desc ($n)"
  else
    _fail_with_artifacts "$desc"
  fi
}

# assert_proc <name> [desc] — a process matching <name> is running (pgrep -f).
assert_proc() {
  local name="$1"; local desc="${2:-process running: $name}"
  if pgrep -f "$name" >/dev/null 2>&1; then
    pass "$desc"
  else
    _fail_with_artifacts "$desc"
  fi
}

# wait_for_unit_active <unit> <timeout-seconds> — poll until a `systemctl --user`
# unit reports active or the timeout elapses. Useful for D-Bus-activated units
# (e.g. xdg-desktop-portal.service) that start on demand rather than at boot:
# touching them to trigger activation, then waiting, is more robust than a bare
# point-in-time read. Returns 0 if active, 1 on timeout. Emits no TAP line.
wait_for_unit_active() {
  local unit="$1"; local timeout="${2:-5}"
  local deadline=$(( $(date +%s) + timeout ))
  while (( $(date +%s) < deadline )); do
    [[ "$(systemctl --user is-active "$unit" 2>/dev/null)" == "active" ]] && return 0
    sleep 0.2
  done
  return 1
}

# assert_unit_active <unit> [desc] — a `systemctl --user` unit is active.
assert_unit_active() {
  local unit="$1"; local desc="${2:-user unit active: $unit}"
  if [[ "$(systemctl --user is-active "$unit" 2>/dev/null)" == "active" ]]; then
    pass "$desc"
  else
    _fail_with_artifacts "$desc"
  fi
}

# assert_dbus_name <name> [desc] — a D-Bus name is owned or activatable on the
# user bus (busctl --user list). Use to confirm a service is reachable even when
# its backing systemd unit is dbus-activated and idle.
assert_dbus_name() {
  local name="$1"; local desc="${2:-D-Bus name available: $name}"
  if busctl --user list 2>/dev/null | grep -q "^$name "; then
    pass "$desc"
  else
    _fail_with_artifacts "$desc"
  fi
}
