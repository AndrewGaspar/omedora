#!/bin/bash
#
# L1 test for monado-xreal's power-saver guard (#14), a stopgap until Monado
# runs well without turbo: monado-xreal-avoid-power-saver.service and its
# helper, /usr/libexec/monado-xreal/avoid-power-saver.
#
# Checks the unit wiring (monado-xreal.service pulls the unit in with Wants=,
# the unit is a oneshot BindsTo= the runtime, so ExecStop= runs however the
# runtime ends), the packaging, and the helper itself. The helper runs against
# a stub busctl that stands in for the PowerProfiles daemon: "enter" must
# switch only power-saver to balanced, "leave" must restore power-saver only
# when "enter" switched and the profile is still balanced, and every failure
# must log and exit 0. The real systemd, polkit and tuned-ppd behaviour is
# verified in Fedora containers; see omedora/packages.md.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
HELPER="$COPR/monado-xreal-avoid-power-saver"
UNIT="$COPR/monado-xreal-avoid-power-saver.service"
RUNTIME_UNIT="$COPR/monado-xreal.service"
SPEC="$COPR/monado-xreal.spec"
SESSION_SPEC="$COPR/hypxrland-omedora.spec"
LIBEXEC_HELPER=/usr/libexec/monado-xreal/avoid-power-saver

assert_file_exists "avoid-power-saver helper exists" "$HELPER"
assert_file_exists "avoid-power-saver unit exists" "$UNIT"
[[ -x $HELPER ]] && pass "helper is executable" || fail "helper is executable"
[[ $(head -1 "$HELPER") == "#!/bin/bash" ]] \
  && pass "helper is a bash script" || fail "helper is a bash script"
bash -n "$HELPER" && pass "helper parses" || fail "helper parses"

# --- unit wiring ------------------------------------------------------------------
grep -qx 'Wants=monado-xreal-avoid-power-saver.service' "$RUNTIME_UNIT" \
  && pass "monado-xreal.service pulls the unit in with Wants=" \
  || fail "monado-xreal.service pulls the unit in with Wants="
if grep -E '^(Requires|Requisite|BindsTo|After|Upholds)=.*avoid-power-saver' "$RUNTIME_UNIT"; then
  fail "monado-xreal.service never depends on or waits for the unit"
else
  pass "monado-xreal.service never depends on or waits for the unit"
fi
assert_equals "the runtime mentions the unit on exactly one directive line" \
  "$(grep -v '^#' "$RUNTIME_UNIT" | grep -c 'avoid-power-saver')" "1"
grep -qx 'BindsTo=monado-xreal.service' "$UNIT" \
  && pass "unit is bound to the runtime" || fail "unit is bound to the runtime"
grep -qx 'After=monado-xreal.service' "$UNIT" \
  && pass "unit starts after the runtime" || fail "unit starts after the runtime"
grep -qx 'Type=oneshot' "$UNIT" && grep -qx 'RemainAfterExit=yes' "$UNIT" \
  && pass "unit is a oneshot that stays active, so stopping it runs ExecStop=" \
  || fail "unit is a oneshot that stays active, so stopping it runs ExecStop="
grep -qx "ExecStart=$LIBEXEC_HELPER enter" "$UNIT" \
  && grep -qx "ExecStop=$LIBEXEC_HELPER leave" "$UNIT" \
  && pass "unit runs the packaged helper's enter and leave" \
  || fail "unit runs the packaged helper's enter and leave"
grep -qx 'RuntimeDirectory=monado-xreal-avoid-power-saver' "$UNIT" \
  && pass "unit gives the helper a runtime directory for its marker" \
  || fail "unit gives the helper a runtime directory for its marker"
grep -qx 'Conflicts=monado-xreal-performance-hold.service' "$UNIT" \
  && grep -qx 'After=monado-xreal-performance-hold.service' "$UNIT" \
  && pass "unit stops a -4 hold an upgrade left running, before reading the profile" \
  || fail "unit stops a -4 hold an upgrade left running, before reading the profile"
if grep -q '^\[Install\]' "$UNIT"; then
  fail "unit has no [Install]: only the runtime pulls it in"
else
  pass "unit has no [Install]: only the runtime pulls it in"
fi

# --- packaging --------------------------------------------------------------------
grep -qE '^Source4:[[:space:]]+monado-xreal-avoid-power-saver\.service$' "$SPEC" \
  && grep -qE '^Source5:[[:space:]]+monado-xreal-avoid-power-saver$' "$SPEC" \
  && pass "monado-xreal ships the unit and helper as sources" \
  || fail "monado-xreal ships the unit and helper as sources"
grep -qF '%{buildroot}%{_userunitdir}/monado-xreal-avoid-power-saver.service' "$SPEC" \
  && grep -qF '%{buildroot}%{_libexecdir}/monado-xreal/avoid-power-saver' "$SPEC" \
  && grep -qx '%{_userunitdir}/monado-xreal-avoid-power-saver.service' "$SPEC" \
  && pass "monado-xreal installs and owns the unit and helper" \
  || fail "monado-xreal installs and owns the unit and helper"
grep -qE '^Requires:[[:space:]]+/usr/bin/busctl$' "$SPEC" \
  && grep -qE '^BuildRequires:[[:space:]]+/usr/bin/busctl$' "$SPEC" \
  && pass "monado-xreal requires busctl for the helper" \
  || fail "monado-xreal requires busctl for the helper"
if sed '/^%changelog/,$d' "$SPEC" | grep -qE 'python3-gobject|performance-hold'; then
  fail "monado-xreal no longer ships the performance hold or needs PyGObject"
else
  pass "monado-xreal no longer ships the performance hold or needs PyGObject"
fi
if [[ -e $COPR/monado-xreal-performance-hold || -e $COPR/monado-xreal-performance-hold.service ]]; then
  fail "the performance hold's sources are gone"
else
  pass "the performance hold's sources are gone"
fi
grep -qF 'systemctl --user mask monado-xreal-avoid-power-saver.service' \
  "$COPR/monado-xreal.README.package.md" \
  && pass "the opt-out is documented in README.package.md" \
  || fail "the opt-out is documented in README.package.md"
if sed -n '/^%check/,/^%files/p' "$SPEC" | grep -qE '^[[:space:]]*! '; then
  fail "%check has no bare negated commands (they never fail the build)"
else
  pass "%check has no bare negated commands (they never fail the build)"
fi
# The power profile is the runtime's business; the XR session starts nothing.
# (The spec's %changelog keeps the history, so it is left out.)
if [[ -e $COPR/hypxr-performance-hold ]] \
  || cat "$COPR/omarchy-xr-session" <(sed '/^%changelog/,$d' "$SESSION_SPEC") |
    grep -qiE 'performance.hold|PERFORMANCE_HOLD|power-saver|setsid|python3-gobject'; then
  fail "the XR session carries no power-profile handling of its own"
else
  pass "the XR session carries no power-profile handling of its own"
fi
grep -qE '^Requires:[[:space:]]+monado-xreal >= 25\.1\.0\^20261016\.2\.git613d8eeb1-4$' "$SESSION_SPEC" \
  && pass "the XR session requires a monado-xreal that manages the profile" \
  || fail "the XR session requires a monado-xreal that manages the profile"

# --- the helper, against a stub busctl ------------------------------------------------
SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/xr-avoid-test.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/bin" "$SCRATCH/rt" "$SCRATCH/pp"

# State lives in $FAKE_PP: "active" (the profile), "holds" (the
# ActiveProfileHolds reply), and the flags no-daemon, refuse, no-holds-prop and
# garbled. Every call is appended to "calls".
cat >"$SCRATCH/bin/busctl" <<'EOF'
#!/bin/bash
d=$FAKE_PP
printf '%s\n' "$*" >>"$d/calls"
args=()
for a in "$@"; do
  [[ $a == --system || $a == --timeout=* ]] || args+=("$a")
done
if [[ ${args[1]} != org.freedesktop.UPower.PowerProfiles \
  || ${args[2]} != /org/freedesktop/UPower/PowerProfiles \
  || ${args[3]} != org.freedesktop.UPower.PowerProfiles ]]; then
  echo "unexpected destination: $*" >&2
  exit 1
fi
if [[ -e $d/no-daemon ]]; then
  echo "Failed to get property: Could not activate remote peer" >&2
  exit 1
fi
case ${args[0]}:${args[4]} in
  get-property:ActiveProfile)
    if [[ -e $d/garbled ]]; then echo "v 42"; else echo "s \"$(<"$d/active")\""; fi ;;
  get-property:ActiveProfileHolds)
    if [[ -e $d/no-holds-prop ]]; then echo "Unknown property" >&2; exit 1; fi
    cat "$d/holds" ;;
  set-property:ActiveProfile)
    [[ ${args[5]} == s ]] || exit 1
    if [[ -e $d/refuse ]]; then
      echo "Failed to set property ActiveProfile: Unauthorized" >&2
      exit 1
    fi
    printf '%s\n' "${args[6]}" >"$d/active" ;;
  *) echo "unexpected call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$SCRATCH/bin/busctl"

export FAKE_PP="$SCRATCH/pp"
MARKER="$SCRATCH/rt/switched-to-balanced"

reset() { # <profile>
  rm -f "$FAKE_PP"/* "$MARKER"
  printf '%s\n' "$1" >"$FAKE_PP/active"
  echo 'aa{sv} 0' >"$FAKE_PP/holds"
  : >"$FAKE_PP/calls"
}
run() { # <step> -> sets $out and $status
  status=0
  out=$(PATH="$SCRATCH/bin:$PATH" RUNTIME_DIRECTORY="$SCRATCH/rt" \
    timeout 20 "$HELPER" "$1" 2>&1) || status=$?
}
active() { cat "$FAKE_PP/active"; }
sets() { grep -c '^--system --timeout=10 set-property' "$FAKE_PP/calls" || true; }

status=0
PATH="$SCRATCH/bin:$PATH" RUNTIME_DIRECTORY="$SCRATCH/rt" "$HELPER" >/dev/null 2>&1 || status=$?
assert_equals "helper without a step exits with usage status 2" "$status" "2"
status=0
PATH="$SCRATCH/bin:$PATH" RUNTIME_DIRECTORY="$SCRATCH/rt" "$HELPER" hold >/dev/null 2>&1 || status=$?
assert_equals "helper with an unknown step exits with usage status 2" "$status" "2"

# power-saver: switched for the session, restored after.
reset power-saver
run enter
assert_equals "enter exits 0" "$status" "0"
assert_equals "enter switches power-saver to balanced" "$(active)" "balanced"
assert_file_exists "enter leaves the marker" "$MARKER"
assert_output_contains "enter logs the switch" "$out" "switched power-saver to balanced"
run leave
assert_equals "leave exits 0" "$status" "0"
assert_equals "leave restores power-saver" "$(active)" "power-saver"
[[ ! -e $MARKER ]] && pass "leave removes the marker" || fail "leave removes the marker"
assert_output_contains "leave logs the restore" "$out" "restored power-saver"
run leave
assert_equals "a second leave changes nothing (two switches in all)" "$(sets):$(active)" "2:power-saver"

# Any other starting profile is left alone, on enter and on leave.
for profile in balanced performance; do
  reset "$profile"
  run enter
  assert_equals "enter leaves $profile alone" "$status:$(active):$(sets)" "0:$profile:0"
  [[ ! -e $MARKER ]] && pass "no marker when starting at $profile" \
    || fail "no marker when starting at $profile"
  run leave
  assert_equals "leave leaves $profile alone" "$status:$(active):$(sets)" "0:$profile:0"
done

# A profile picked during the session stays.
for profile in performance power-saver; do
  reset power-saver
  run enter
  printf '%s\n' "$profile" >"$FAKE_PP/active"
  run leave
  assert_equals "leave keeps $profile picked mid-session" "$status:$(active):$(sets)" "0:$profile:1"
  assert_output_contains "leave logs why it kept $profile" "$out" "changed to $profile"
done

# Without a marker (enter never switched), leave never touches balanced.
reset balanced
run leave
assert_equals "leave without a marker does nothing" "$status:$(active):$(sets)" "0:balanced:0"

# A held power-saver (a low-battery policy, say) is not cancelled.
reset power-saver
echo 'aa{sv} 1 3 "Profile" s "power-saver" "Reason" s "low battery" "ApplicationId" s "x"' >"$FAKE_PP/holds"
run enter
assert_equals "enter leaves a held power-saver alone" "$status:$(active):$(sets)" "0:power-saver:0"
assert_output_contains "enter logs the hold" "$out" "held by another application"

# A daemon without ActiveProfileHolds has no holds to cancel.
reset power-saver
: >"$FAKE_PP/no-holds-prop"
run enter
assert_equals "enter switches when the daemon has no holds property" "$status:$(active)" "0:balanced"

# Fail open: no daemon, a polkit refusal, a reply it cannot parse, no runtime dir.
reset power-saver
: >"$FAKE_PP/no-daemon"
run enter
assert_equals "enter exits 0 with no daemon" "$status" "0"
assert_output_contains "enter logs the missing daemon" "$out" "cannot read the active power profile"
[[ ! -e $MARKER ]] && pass "no marker with no daemon" || fail "no marker with no daemon"

reset power-saver
: >"$FAKE_PP/refuse"
run enter
assert_equals "enter exits 0 when polkit refuses" "$status:$(active)" "0:power-saver"
assert_output_contains "enter logs the refusal" "$out" "Unauthorized"
[[ ! -e $MARKER ]] && pass "no marker when the switch is refused" \
  || fail "no marker when the switch is refused"

reset power-saver
run enter
: >"$FAKE_PP/refuse"
run leave
assert_equals "leave exits 0 when polkit refuses the restore" "$status:$(active)" "0:balanced"
assert_output_contains "leave logs the refusal" "$out" "cannot switch to power-saver"

reset power-saver
run enter
: >"$FAKE_PP/no-daemon"
run leave
assert_equals "leave exits 0 when the daemon went away" "$status" "0"
[[ ! -e $MARKER ]] && pass "leave drops the marker even when it cannot restore" \
  || fail "leave drops the marker even when it cannot restore"

reset power-saver
: >"$FAKE_PP/garbled"
run enter
assert_equals "enter exits 0 on a reply it cannot parse" "$status:$(sets)" "0:0"
assert_output_contains "enter logs the reply" "$out" "unexpected ActiveProfile reply"

reset power-saver
status=0
out=$(PATH="$SCRATCH/bin:$PATH" RUNTIME_DIRECTORY= "$HELPER" enter 2>&1) || status=$?
assert_equals "enter exits 0 without a runtime directory, switching nothing" \
  "$status:$(active):$(sets)" "0:power-saver:0"
assert_output_contains "enter logs the missing runtime directory" "$out" "no runtime directory"

# The %check run: no stub, a bus address that does not exist.
status=0
out=$(RUNTIME_DIRECTORY="$SCRATCH/rt" DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SCRATCH/no-such-bus" \
  timeout 20 "$HELPER" enter 2>&1) || status=$?
assert_equals "enter exits 0 with the real busctl (or none) and no system bus" "$status" "0"
assert_output_contains "enter logs why it did not switch" "$out" "cannot read the active power profile"

echo "# all monado-xreal avoid-power-saver tests passed"
