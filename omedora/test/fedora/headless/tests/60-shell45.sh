#!/bin/bash
#
# L4-headless: Omarchy 4.5's session-start and notification behavior on Fedora.
#
#   1. Startup cursor: the compositor starts with a blank cursor theme
#      (XCURSOR_THEME=omarchy-startup, cursor:invisible) until the shell's
#      background intro reveals the desktop, then restores the user's cursor
#      (default/hypr/startup-cursor.lua, shell/services/BackgroundIntro.qml).
#      Both must be undone within ~20 s of the compositor starting.
#   2. Notifications: org.freedesktop.Notifications on the user bus belongs to
#      the Quickshell shell. On Fedora Workstation another daemon could be
#      D-Bus activated first and silently swallow every notification.
#   3. omarchy-notification-send puts a toast on screen through that server.
#   4. Hyprland carries the omarchy:shift_caps_compose keyboard option.
#
# Runs on both the standard and the --workstation base.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

monotonic_us() { python3 -c 'import time; print(int(time.monotonic() * 1e6))'; }

# --- 1. startup cursor restored ------------------------------------------------
wm_unit=$(systemd-escape --template=wayland-wm@.service start-hyprland)
started_us=$(systemctl --user show -p ExecMainStartTimestampMonotonic --value "$wm_unit" 2>/dev/null)
[[ $started_us =~ ^[0-9]+$ && $started_us != 0 ]] || started_us=$(monotonic_us)
deadline_us=$((started_us + 25 * 1000000))

cursor_invisible() {
  hyprctl getoption cursor:invisible -j 2>/dev/null | python3 -c '
import json, sys
try:
  d = json.load(sys.stdin)
except Exception:
  print("?"); sys.exit()
for key in ("int", "bool", "str"):
  if key in d:
    v = d[key]
    print(1 if v in (1, True, "true", "1") else 0)
    break
else:
  print("?")'
}

# The compositor's own environment, as the next child it spawns would see it.
compositor_cursor_theme() {
  local out="$ARTIFACTS/compositor-xcursor.txt"
  rm -f "$out"
  hyprctl eval "hl.exec_cmd('printenv XCURSOR_THEME >$out; echo end >>$out')" >/dev/null 2>&1 || return 1
  for _ in $(seq 1 20); do
    grep -qx end "$out" 2>/dev/null && { head -n -1 "$out"; return 0; }
    sleep 0.1
  done
  return 1
}

restored=false
while :; do
  invisible=$(cursor_invisible)
  theme=$(compositor_cursor_theme || echo "?")
  if [[ $invisible == 0 && $theme != "omarchy-startup" && $theme != "?" ]]; then
    restored=true
    break
  fi
  (( $(monotonic_us) < deadline_us )) || break
  sleep 0.5
done
elapsed=$(( ($(monotonic_us) - started_us) / 1000000 ))
if $restored; then
  # Run first (--test '60-*') this shows the real reveal time: the shell's own
  # fallback fires at 10s and the compositor's at 15s, so a value below 10s
  # means the background intro, not a fallback, restored the cursor.
  pass "the startup cursor is restored (cursor:invisible=0, XCURSOR_THEME=${theme:-unset}; observed ${elapsed}s after compositor start)"
else
  _fail_with_artifacts "the startup cursor is restored within ~20s (cursor:invisible=$invisible, XCURSOR_THEME=$theme after ${elapsed}s)"
fi
session_theme=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^XCURSOR_THEME=//p')
[[ $session_theme != "omarchy-startup" ]] \
  && pass "the user manager's environment no longer carries the startup cursor (XCURSOR_THEME=${session_theme:-unset})" \
  || _fail_with_artifacts "the user manager's environment no longer carries the startup cursor"
[[ -s ${HOME}/.local/state/omarchy/background-intro.session-id ]] \
  && pass "the background intro recorded this session as revealed" \
  || _fail_with_artifacts "the background intro recorded this session as revealed"

# --- 2. the shell owns the notification server ------------------------------------
owner=""
for _ in $(seq 1 20); do
  owner=$(busctl --user list --no-legend 2>/dev/null | awk '$1 == "org.freedesktop.Notifications" && $2 ~ /^[0-9]+$/ {print $2; exit}')
  [[ -n $owner ]] && break
  sleep 0.5
done
owner_comm=$([[ -n $owner ]] && ps -o comm= -p "$owner" 2>/dev/null)
busctl --user list --no-legend 2>/dev/null | grep -i notif >"$ARTIFACTS/notification-names.txt" || true
if [[ $owner_comm == quickshell* || $owner_comm == .quickshell* ]]; then
  pass "org.freedesktop.Notifications is owned by the Quickshell shell (pid $owner)"
else
  _fail_with_artifacts "org.freedesktop.Notifications is owned by the Quickshell shell (owner: ${owner_comm:-none} pid ${owner:-none})"
fi
mapfile -t activatable < <(grep -lsx 'Name=org.freedesktop.Notifications' \
  /usr/share/dbus-1/services/*.service "$HOME"/.local/share/dbus-1/services/*.service 2>/dev/null)
echo "# activatable notification servers: ${activatable[*]:-none}"

# --- 3. omarchy-notification-send shows a toast ------------------------------------
dnd=$(omarchy-shell notifications isDnd 2>/dev/null || echo "?")
[[ $dnd == on ]] && omarchy-shell notifications setDnd off >/dev/null 2>&1
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
headline="Omedora L4 toast $$"
if omarchy-notification-send "$headline" "60-shell45 check" >"$ARTIFACTS/notification-send.log" 2>&1; then
  pass "omarchy-notification-send exits 0"
else
  _fail_with_artifacts "omarchy-notification-send exits 0"
fi
shown=0
for _ in $(seq 1 20); do
  shown=$(omarchy-shell notifications count 2>/dev/null || echo 0)
  [[ $shown =~ ^[0-9]+$ ]] || shown=0
  (( shown > 0 )) && break
  sleep 0.25
done
wait_for_layer omarchy-notifications 5 || true
assert_layer omarchy-notifications "the toast maps the omarchy-notifications layer"
(( shown > 0 )) && screenshot "60-shell45-toast"
dismissed=$(omarchy-shell notifications dismiss "$headline" 2>/dev/null || echo none)
assert_equals "the shell shows the sent toast (dismissed by its headline)" "$dismissed" "ok"
[[ $dnd == on ]] && omarchy-shell notifications setDnd on >/dev/null 2>&1

# --- 4. Shift+Caps compose option reached the compositor ---------------------------
# L2 (xkb-compose-integration.sh) proves the option compiles; here the live
# compositor carries it. Hyprland rejects a keymap that fails to compile and
# falls back, so a compile failure would also show in the error log.
kb_options=$(hyprctl getoption input:kb_options -j 2>/dev/null | jq -r '.str // empty')
assert_output_contains "Hyprland carries the Shift+Caps compose option" "$kb_options" "omarchy:shift_caps_compose"
