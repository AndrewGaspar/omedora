#!/bin/bash
#
# L4-headless acceptance test for Omarchy 4.5's media tools on Fedora.
#
#   1. Screenshots: omarchy-capture-screenshot execs omasnap (4.5 replaced
#      satty/tensaku with it). A fullscreen quick save needs no interaction, so
#      it proves the whole path: the omasnap RPM, LayerShellQt, the
#      ext-image-copy-capture protocol in our Hyprland, and the PNG writer.
#   2. Wallpaper engine: first-run enables owe's owed.service and owe answers
#      on its socket.
#   3. Theme intros: owe plays each theme's intro clip through libmpv, and these
#      are H.264 High profile. Decode every shipped intro with the installed
#      libavcodec (ffmpeg, the same library libmpv uses) and with mpv itself,
#      so a codec stack that can't decode them fails here instead of showing a
#      blank intro.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

# --- 1. omasnap fullscreen screenshot ------------------------------------------
shots=$(mktemp -d)
OMASNAP_SCREENSHOT_DIR="$shots" timeout 20 omarchy-capture-screenshot fullscreen save \
  >"$ARTIFACTS/omasnap.log" 2>&1 || true
shot=""
for _ in $(seq 1 40); do
  shot=$(find "$shots" -name '*.png' -size +10k -print -quit)
  [[ -n $shot ]] && break
  sleep 0.25
done
if [[ -n $shot ]]; then
  cp "$shot" "$ARTIFACTS/omasnap-fullscreen.png" 2>/dev/null || true
  pass "omarchy-capture-screenshot saves a fullscreen PNG through omasnap"
else
  _fail_with_artifacts "omarchy-capture-screenshot saves a fullscreen PNG through omasnap"
fi
if [[ -n $shot ]] && command -v identify >/dev/null; then
  geometry=$(identify -format '%wx%h' "$shot" 2>/dev/null)
  monitor=$(hyprctl monitors -j | python3 -c 'import sys,json; m=json.load(sys.stdin)[0]; print(f"{m[\"width\"]}x{m[\"height\"]}")')
  [[ $geometry == "$monitor" ]] \
    && pass "the omasnap capture covers the whole output ($geometry)" \
    || _fail_with_artifacts "the omasnap capture covers the whole output (got $geometry, output $monitor)"
fi
rm -rf "$shots"

# --- 2. owe daemon ---------------------------------------------------------------
wait_for_unit_active owed.service 10
assert_unit_active owed.service "owe's owed.service is enabled and running"
if timeout 5 owe status >"$ARTIFACTS/owe-status.txt" 2>&1; then
  pass "owe answers on its socket (owe status)"
else
  _fail_with_artifacts "owe answers on its socket (owe status)"
fi

# --- 3. theme intro clips decode ----------------------------------------------
mapfile -t intros < <(find "${OMARCHY_PATH:-/usr/share/omarchy}"/themes/*/backgrounds/intros -name '*.mp4' 2>/dev/null | sort)
if (( ${#intros[@]} == 0 )); then
  _fail_with_artifacts "the theme intro clips are installed"
else
  pass "the theme intro clips are installed (${#intros[@]})"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile \
    -of csv=p=0 "${intros[0]}" >"$ARTIFACTS/intro-codec.txt" 2>&1 || true
  bad=()
  for intro in "${intros[@]}"; do
    ffmpeg -nostdin -v error -i "$intro" -frames:v 10 -f null - >>"$ARTIFACTS/intro-ffmpeg.log" 2>&1 \
      || bad+=("${intro#*/themes/}")
  done
  (( ${#bad[@]} == 0 )) \
    && pass "every intro decodes with the installed libavcodec ($(<"$ARTIFACTS/intro-codec.txt"))" \
    || _fail_with_artifacts "every intro decodes with the installed libavcodec (failed: ${bad[*]})"
  if timeout 30 mpv --no-config --really-quiet --vo=null --ao=null --hwdec=no --frames=10 \
    "${intros[0]}" >"$ARTIFACTS/intro-mpv.log" 2>&1; then
    pass "mpv (libmpv's decoder stack) plays an intro"
  else
    _fail_with_artifacts "mpv (libmpv's decoder stack) plays an intro"
  fi
fi
