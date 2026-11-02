#!/bin/bash
#
# L1 behavior test for the Omedora XR session's performance-profile hold (#12):
# omarchy-xr-session (hypxrland-omedora) and its performance-hold helper.
#
# The wrapper is run from a copy whose /usr paths point at stubs, so this needs
# no XR stack, power-profiles daemon or system bus. It checks that the helper
# is started detached with the PID the session keeps after exec, that the opt-out
# skips it, and that a failing or missing helper never stops the session.
# The helper is run against a bus address that does not exist, so it must fail
# open: log and exit 0 whether or not PyGObject is installed. The real hold
# (tuned-ppd granting and dropping it) is verified in Fedora containers; see
# omedora/packages.md.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
WRAPPER="$COPR/omarchy-xr-session"
HOLD="$COPR/hypxr-performance-hold"
SPEC="$COPR/hypxrland-omedora.spec"

assert_file_exists "omarchy-xr-session exists" "$WRAPPER"
assert_file_exists "performance-hold helper exists" "$HOLD"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/xr-hold-test.XXXXXX")
trap 'rm -rf "$SCRATCH"' EXIT

# --- the wrapper, against stubs -------------------------------------------------
mkdir -p "$SCRATCH/home/.config/hypr"
: >"$SCRATCH/home/.config/hypr/hyprland-xr.lua"
cat >"$SCRATCH/session" <<EOF
#!/bin/bash
echo "\$\$" >"$SCRATCH/session.pid"
echo "\$*" >"$SCRATCH/session.args"
EOF
cat >"$SCRATCH/hold-ok" <<EOF
#!/bin/bash
echo "\$*" >"$SCRATCH/hold.args"
EOF
cat >"$SCRATCH/hold-fails" <<EOF
#!/bin/bash
echo "\$*" >"$SCRATCH/hold.args"
exit 1
EOF
chmod +x "$SCRATCH/session" "$SCRATCH/hold-ok" "$SCRATCH/hold-fails"

stub_wrapper() { # <helper path>
  sed -e "s|/usr/bin/hypxrland-session|$SCRATCH/session|" \
    -e "s|/usr/bin/omarchy-setup-hypxrland|false|" \
    -e "s|/usr/libexec/hypxrland-omedora/performance-hold|$1|" \
    "$WRAPPER" >"$SCRATCH/wrapper"
  chmod +x "$SCRATCH/wrapper"
}

run_wrapper() { # [env assignments...]
  rm -f "$SCRATCH/session.pid" "$SCRATCH/session.args" "$SCRATCH/hold.args"
  env -u OMEDORA_XR_PERFORMANCE_HOLD HOME="$SCRATCH/home" XDG_CONFIG_HOME= "$@" \
    "$SCRATCH/wrapper" --flag value
}

wait_for_file() { # <path>
  local tries
  for (( tries = 0; tries < 50; tries++ )); do
    [[ -s $1 ]] && return 0
    sleep 0.1
  done
  return 1
}

grep -qF '/usr/libexec/hypxrland-omedora/performance-hold' "$WRAPPER" \
  && pass "wrapper starts the packaged helper" || fail "wrapper starts the packaged helper"

stub_wrapper "$SCRATCH/hold-ok"
run_wrapper
wait_for_file "$SCRATCH/hold.args" \
  && pass "helper runs by default" || fail "helper runs by default"
assert_equals "helper watches the PID the session keeps after exec" \
  "$(cat "$SCRATCH/session.pid")" "$(cat "$SCRATCH/hold.args")"
assert_equals "session gets the wrapper's arguments" "--flag value" "$(cat "$SCRATCH/session.args")"

run_wrapper OMEDORA_XR_PERFORMANCE_HOLD=0
[[ -s $SCRATCH/session.pid ]] \
  && pass "opted-out session still starts" || fail "opted-out session still starts"
sleep 0.5
[[ ! -e $SCRATCH/hold.args ]] \
  && pass "OMEDORA_XR_PERFORMANCE_HOLD=0 skips the hold" \
  || fail "OMEDORA_XR_PERFORMANCE_HOLD=0 skips the hold"

run_wrapper OMEDORA_XR_PERFORMANCE_HOLD=1
wait_for_file "$SCRATCH/hold.args" \
  && pass "any other value keeps the hold" || fail "any other value keeps the hold"

stub_wrapper "$SCRATCH/hold-fails"
run_wrapper
[[ -s $SCRATCH/session.pid ]] \
  && pass "a failing helper does not stop the session" \
  || fail "a failing helper does not stop the session"

stub_wrapper "$SCRATCH/does-not-exist"
run_wrapper 2>/dev/null
[[ -s $SCRATCH/session.pid ]] \
  && pass "a missing helper does not stop the session" \
  || fail "a missing helper does not stop the session"

# --- the helper fails open ------------------------------------------------------
status=0
python3 -I "$HOLD" >/dev/null 2>&1 || status=$?
assert_equals "helper rejects a missing PID with usage status 2" "2" "$status"

sleep 2 &
sleeper=$!
status=0
out=$(DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SCRATCH/no-such-bus" \
  timeout 20 python3 -I "$HOLD" "$sleeper" 2>&1) || status=$?
assert_equals "helper exits 0 when no daemon grants the hold" "0" "$status"
assert_output_contains "helper logs why it is not holding" "$out" "not holding"
wait "$sleeper" || true
status=0
out=$(python3 -I "$HOLD" "$sleeper" 2>&1) || status=$?
assert_equals "helper exits 0 when the session is already gone" "0" "$status"
assert_output_contains "helper logs the gone session" "$out" "cannot watch the session process"

# --- the helper's contract with the daemon ---------------------------------------
grep -qF '"HoldProfile"' "$HOLD" && grep -qF '"ReleaseProfile"' "$HOLD" \
  && pass "helper uses the PowerProfiles hold API" \
  || fail "helper uses the PowerProfiles hold API"
grep -qF 'BUS_NAME = "org.freedesktop.UPower.PowerProfiles"' "$HOLD" \
  && grep -qF 'PROFILE = "performance"' "$HOLD" \
  && pass "helper holds performance on org.freedesktop.UPower.PowerProfiles" \
  || fail "helper holds performance on org.freedesktop.UPower.PowerProfiles"
grep -qF 'os.pidfd_open(pid)' "$HOLD" \
  && pass "helper watches the session with a pidfd" \
  || fail "helper watches the session with a pidfd"

# --- packaging --------------------------------------------------------------------
grep -qE '^Source4:[[:space:]]+hypxr-performance-hold$' "$SPEC" \
  && grep -qF '%{buildroot}%{_libexecdir}/hypxrland-omedora/performance-hold' "$SPEC" \
  && pass "hypxrland-omedora installs the helper" \
  || fail "hypxrland-omedora installs the helper"
grep -qE '^Requires:[[:space:]]+python3-gobject-base$' "$SPEC" \
  && grep -qE '^Requires:[[:space:]]+/usr/bin/setsid$' "$SPEC" \
  && pass "hypxrland-omedora requires PyGObject and setsid" \
  || fail "hypxrland-omedora requires PyGObject and setsid"
grep -qF 'OMEDORA_XR_PERFORMANCE_HOLD=0' "$SPEC" \
  && pass "the opt-out is documented in the package description" \
  || fail "the opt-out is documented in the package description"
if sed -n '/^%check/,/^%files/p' "$SPEC" | grep -qE '^[[:space:]]*! '; then
  fail "%check has no bare negated commands (they never fail the build)"
else
  pass "%check has no bare negated commands (they never fail the build)"
fi

echo "# all XR session performance-hold tests passed"
