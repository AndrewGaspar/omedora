#!/bin/bash
#
# L1 guard: upstream's session-unit drop-ins reach Omedora's real compositor
# unit.
#
# Upstream ships etc/systemd/user/wayland-wm@hyprland.desktop.service.d/
# 10-keep-shell.conf (KillMode=mixed), so start-hyprland stops Hyprland before
# its shell clients get SIGTERM and the wallpaper survives teardown. uwsm names
# the compositor unit after its main argument's basename. Upstream launches
# hyprland.desktop; omedora.desktop launches `-- start-hyprland`, so the unit
# here is wayland-wm@start\x2dhyprland.service and a drop-in under upstream's
# name would never load. Derive the unit from the session file exactly as uwsm
# does and require omedora-settings to install the drop-in there.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

DESKTOP="$ROOT/omedora/packaging/copr/omedora.desktop"
SPEC="$ROOT/omedora/packaging/copr/omedora-settings.spec"
UPSTREAM_DROPIN="etc/systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf"

assert_file_exists "omedora.desktop exists" "$DESKTOP"
assert_file_exists "upstream keep-shell drop-in exists" "$ROOT/$UPSTREAM_DROPIN"

grep -qx 'KillMode=mixed' "$ROOT/$UPSTREAM_DROPIN" \
  && pass "upstream keep-shell drop-in sets KillMode=mixed" \
  || fail "upstream keep-shell drop-in sets KillMode=mixed"

# uwsm start: the compositor ID is the basename of the first word after `--`
# (uwsm main.py: CompGlobals.id = os.path.basename(wm_cmdline[0])).
exec_line=$(sed -n 's/^Exec=//p' "$DESKTOP")
[[ $exec_line == uwsm\ start* ]] || fail "omedora.desktop launches through uwsm start"
read -r -a exec_words <<<"$exec_line"
wm_cmd=""
for (( i = 0; i < ${#exec_words[@]}; i++ )); do
  if [[ ${exec_words[i]} == "--" ]]; then
    wm_cmd=${exec_words[i + 1]:-}
    break
  fi
done
[[ -n $wm_cmd ]] || fail "omedora.desktop names the compositor after --"
wm_id=${wm_cmd##*/}

if command -v systemd-escape >/dev/null 2>&1; then
  unit=$(systemd-escape --template=wayland-wm@.service "$wm_id")
else
  # Same escaping for a plain basename: everything outside [A-Za-z0-9:_.] is
  # \xNN (uwsm simple_systemd_escape with start=False).
  escaped=""
  for (( i = 0; i < ${#wm_id}; i++ )); do
    ch=${wm_id:i:1}
    if [[ $ch =~ [A-Za-z0-9:_.] ]]; then
      escaped+=$ch
    else
      printf -v hex '\\x%02x' "'$ch"
      escaped+=$hex
    fi
  done
  unit="wayland-wm@$escaped.service"
fi
assert_equals "omedora.desktop's compositor unit" "$unit" 'wayland-wm@start\x2dhyprland.service'

# %install: copies upstream's drop-in into <unit>.d under the user unit dir.
install_line=$(grep -F "$UPSTREAM_DROPIN" "$SPEC" -A1 | tr -d '\n' || true)
[[ -n $install_line ]] || fail "omedora-settings.spec installs upstream's keep-shell drop-in"
dest=$(grep -oE "%\{_userunitdir\}/['\"]?wayland-wm@[^ ]*10-keep-shell\.conf" <<<"$install_line" | head -1)
dest=${dest#%\{_userunitdir\}/}
dest=${dest//\'/}
dest=${dest//\"/}
assert_equals "the drop-in installs under the real unit name" "$dest" "$unit.d/10-keep-shell.conf"

# %files: the listed path (an rpm glob, since the name holds a backslash) must
# match the installed name and nothing named for upstream's hyprland.desktop.
files_pattern=$(awk '/^%files/{f=1} f' "$SPEC" | grep -oE '^%\{_userunitdir\}/wayland-wm@[^ ]*' | head -1 || true)
[[ -n $files_pattern ]] || fail "omedora-settings.spec %files lists the keep-shell drop-in"
files_pattern=${files_pattern#%\{_userunitdir\}/}
if [[ $files_pattern == */ ]]; then
  # shellcheck disable=SC2053 # rpm glob on purpose
  [[ $unit.d/ == $files_pattern ]] || fail "%files dir glob '$files_pattern' matches $unit.d/"
else
  # shellcheck disable=SC2053
  [[ $unit.d/10-keep-shell.conf == $files_pattern ]] \
    || fail "%files glob '$files_pattern' matches $unit.d/10-keep-shell.conf"
fi
pass "%files glob matches the installed drop-in"

if grep -E '^[^#]*wayland-wm@hyprland\.desktop\.service\.d' "$SPEC" | grep -vF "$UPSTREAM_DROPIN" | grep -q .; then
  fail "the spec installs nothing under upstream's unused hyprland.desktop unit name"
fi
pass "the spec installs nothing under upstream's unused hyprland.desktop unit name"

# Every upstream user-unit drop-in directory must be reviewed here: a new one
# needs the same rename (or an explicit decision) before it ships.
mapfile -t upstream_dropins < <(cd "$ROOT" && find etc/systemd/user -mindepth 2 -type f | sort)
assert_equals "upstream ships exactly the reviewed user-unit drop-ins" \
  "${upstream_dropins[*]}" "$UPSTREAM_DROPIN"
