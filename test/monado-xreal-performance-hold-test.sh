#!/bin/bash
#
# L1 test for monado-xreal's performance power-profile hold (#12), a stopgap
# until Monado runs well without turbo: monado-xreal-performance-hold.service
# and its helper, /usr/libexec/monado-xreal/performance-hold.
#
# Checks the unit wiring (monado-xreal.service pulls the hold in with Wants=,
# the hold is BindsTo= the runtime), the packaging, and the helper itself. The
# helper runs against a fake PowerProfiles daemon on a private D-Bus: it must
# hold "performance" until SIGTERM or SIGINT, then release it and exit 0, and
# it must fail open (log, exit 0) when the hold is refused or there is no bus.
# The real systemd and tuned-ppd behaviour is verified in Fedora containers;
# see omedora/packages.md.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
HOLD="$COPR/monado-xreal-performance-hold"
HOLD_UNIT="$COPR/monado-xreal-performance-hold.service"
RUNTIME_UNIT="$COPR/monado-xreal.service"
SPEC="$COPR/monado-xreal.spec"
SESSION_SPEC="$COPR/hypxrland-omedora.spec"

assert_file_exists "performance-hold helper exists" "$HOLD"
assert_file_exists "hold unit exists" "$HOLD_UNIT"
[[ -x $HOLD ]] && pass "helper is executable" || fail "helper is executable"

# --- unit wiring ------------------------------------------------------------------
grep -qx 'Wants=monado-xreal-performance-hold.service' "$RUNTIME_UNIT" \
  && pass "monado-xreal.service pulls the hold in with Wants=" \
  || fail "monado-xreal.service pulls the hold in with Wants="
if grep -E '^(Requires|Requisite|BindsTo|After|Upholds)=.*performance-hold' "$RUNTIME_UNIT"; then
  fail "monado-xreal.service never depends on or waits for the hold"
else
  pass "monado-xreal.service never depends on or waits for the hold"
fi
assert_equals "the runtime mentions the hold on exactly one directive line" \
  "$(grep -v '^#' "$RUNTIME_UNIT" | grep -c 'performance-hold')" "1"
grep -qx 'BindsTo=monado-xreal.service' "$HOLD_UNIT" \
  && pass "hold unit is bound to the runtime" || fail "hold unit is bound to the runtime"
grep -qx 'After=monado-xreal.service' "$HOLD_UNIT" \
  && pass "hold unit starts after the runtime" || fail "hold unit starts after the runtime"
grep -qx 'Type=simple' "$HOLD_UNIT" && grep -qx 'Restart=no' "$HOLD_UNIT" \
  && pass "hold unit is a simple, non-restarting service" \
  || fail "hold unit is a simple, non-restarting service"
grep -qx 'ExecStart=/usr/libexec/monado-xreal/performance-hold' "$HOLD_UNIT" \
  && pass "hold unit runs the packaged helper" || fail "hold unit runs the packaged helper"
if grep -q '^\[Install\]' "$HOLD_UNIT"; then
  fail "hold unit has no [Install]: only the runtime pulls it in"
else
  pass "hold unit has no [Install]: only the runtime pulls it in"
fi

# --- the helper's contract with the daemon ---------------------------------------
grep -qF '"HoldProfile"' "$HOLD" && grep -qF '"ReleaseProfile"' "$HOLD" \
  && pass "helper uses the PowerProfiles hold API" \
  || fail "helper uses the PowerProfiles hold API"
grep -qxF 'BUS_NAME = "org.freedesktop.UPower.PowerProfiles"' "$HOLD" \
  && grep -qxF 'PROFILE = "performance"' "$HOLD" \
  && grep -qxF 'APP_ID = "monado-xreal"' "$HOLD" \
  && grep -qxF 'REASON = "XREAL runtime running"' "$HOLD" \
  && pass "helper holds performance as monado-xreal" \
  || fail "helper holds performance as monado-xreal"
if grep -qE 'pidfd|argv\[1\]' "$HOLD"; then
  fail "helper has no PID-watching mode left"
else
  pass "helper has no PID-watching mode left"
fi

# --- packaging --------------------------------------------------------------------
grep -qE '^Source4:[[:space:]]+monado-xreal-performance-hold\.service$' "$SPEC" \
  && grep -qE '^Source5:[[:space:]]+monado-xreal-performance-hold$' "$SPEC" \
  && pass "monado-xreal ships the hold unit and helper as sources" \
  || fail "monado-xreal ships the hold unit and helper as sources"
grep -qF '%{buildroot}%{_userunitdir}/monado-xreal-performance-hold.service' "$SPEC" \
  && grep -qF '%{buildroot}%{_libexecdir}/monado-xreal/performance-hold' "$SPEC" \
  && grep -qx '%{_userunitdir}/monado-xreal-performance-hold.service' "$SPEC" \
  && pass "monado-xreal installs and owns the hold unit and helper" \
  || fail "monado-xreal installs and owns the hold unit and helper"
grep -qE '^Requires:[[:space:]]+python3-gobject-base$' "$SPEC" \
  && grep -qE '^BuildRequires:[[:space:]]+python3-gobject-base$' "$SPEC" \
  && pass "monado-xreal requires PyGObject for the helper" \
  || fail "monado-xreal requires PyGObject for the helper"
grep -qF 'systemctl --user mask monado-xreal-performance-hold.service' \
  "$COPR/monado-xreal.README.package.md" \
  && pass "the opt-out is documented in README.package.md" \
  || fail "the opt-out is documented in README.package.md"
if sed -n '/^%check/,/^%files/p' "$SPEC" | grep -qE '^[[:space:]]*! '; then
  fail "%check has no bare negated commands (they never fail the build)"
else
  pass "%check has no bare negated commands (they never fail the build)"
fi
# The hold lives only in the runtime now; the XR session no longer starts one.
# (The spec's %changelog keeps the history, so it is left out.)
if [[ -e $COPR/hypxr-performance-hold ]] \
  || cat "$COPR/omarchy-xr-session" <(sed '/^%changelog/,$d' "$SESSION_SPEC") |
    grep -qiE 'performance.hold|PERFORMANCE_HOLD|setsid|python3-gobject'; then
  fail "the XR session carries no hold of its own"
else
  pass "the XR session carries no hold of its own"
fi
grep -qE '^Requires:[[:space:]]+monado-xreal >= 25\.1\.0\^20261016\.2\.git613d8eeb1-4$' "$SESSION_SPEC" \
  && pass "the XR session requires the monado-xreal that holds" \
  || fail "the XR session requires the monado-xreal that holds"

# --- the helper, against a fake PowerProfiles daemon ---------------------------------
status=0
python3 -I "$HOLD" extra >/dev/null 2>&1 || status=$?
assert_equals "helper rejects arguments with usage status 2" "$status" "2"

if ! python3 -I -c 'import gi; from gi.repository import Gio' 2>/dev/null \
  || ! command -v dbus-daemon >/dev/null; then
  if [[ -n ${CI:-} ]]; then
    fail "PyGObject and dbus-daemon are available for the live-bus checks"
  fi
  echo "# SKIP: live-bus checks need PyGObject and dbus-daemon"
  echo "# all monado-xreal performance-hold tests passed"
  exit 0
fi

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/xr-hold-test.XXXXXX")
BUS_PID=
DAEMON_PID=
cleanup() {
  [[ -n $DAEMON_PID ]] && kill "$DAEMON_PID" 2>/dev/null || true
  [[ -n $BUS_PID ]] && kill "$BUS_PID" 2>/dev/null || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

cat >"$SCRATCH/fake-daemon.py" <<'EOF'
import os
import sys
from gi.repository import Gio, GLib

LOG = sys.argv[1]
XML = """<node><interface name="org.freedesktop.UPower.PowerProfiles">
<method name="HoldProfile"><arg type="s" direction="in"/><arg type="s" direction="in"/>
<arg type="s" direction="in"/><arg type="u" direction="out"/></method>
<method name="ReleaseProfile"><arg type="u" direction="in"/></method>
</interface></node>"""


def record(line):
    with open(LOG, "a") as log:
        log.write(line + "\n")


def on_call(conn, sender, path, iface, method, params, invocation):
    if method == "HoldProfile":
        if os.path.exists(LOG + ".refuse"):
            invocation.return_dbus_error("org.freedesktop.DBus.Error.AccessDenied", "refused")
            return
        record("hold " + "|".join(params.unpack()))
        invocation.return_value(GLib.Variant("(u)", (7,)))
    else:
        record("release %d" % params.unpack()[0])
        invocation.return_value(None)


def on_bus(conn, name):
    info = Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0]
    conn.register_object("/org/freedesktop/UPower/PowerProfiles", info, on_call, None, None)


Gio.bus_own_name(Gio.BusType.SYSTEM, "org.freedesktop.UPower.PowerProfiles",
                 Gio.BusNameOwnerFlags.NONE, on_bus, lambda *a: record("ready"), None)
GLib.MainLoop().run()
EOF

dbus-daemon --session --nofork --address="unix:path=$SCRATCH/bus" >/dev/null 2>&1 &
BUS_PID=$!
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SCRATCH/bus"
LOG="$SCRATCH/daemon.log"
for (( tries = 0; tries < 50; tries++ )); do
  [[ -S $SCRATCH/bus ]] && break
  sleep 0.1
done
python3 -I -W ignore::DeprecationWarning "$SCRATCH/fake-daemon.py" "$LOG" &
DAEMON_PID=$!

wait_for_line() { # <line>
  local tries
  for (( tries = 0; tries < 100; tries++ )); do
    grep -qxF -- "$1" "$LOG" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

wait_for_line ready || fail "fake PowerProfiles daemon starts"

# A signal sent to "$!" before bash's forked child has exec'd Python can be
# swallowed by bash itself, so signal only once the helper is really running.
wait_for_exec() { # <pid>
  local tries
  for (( tries = 0; tries < 100; tries++ )); do
    [[ $(tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null) == *"$HOLD"* ]] && return 0
    sleep 0.05
  done
  return 1
}

# Wait at most 20s for <pid> to exit, so a lost signal fails instead of hanging.
wait_bounded() { # <pid>
  timeout 20 tail --pid="$1" -f /dev/null || true
  if kill -0 "$1" 2>/dev/null; then
    kill -9 "$1"
    fail "helper exits after a stop signal"
  fi
}

held_then_stopped() { # <signal>
  : >"$LOG"
  python3 -I "$HOLD" 2>"$SCRATCH/hold.err" &
  local helper=$! status=0
  wait_for_line 'hold performance|XREAL runtime running|monado-xreal' \
    && pass "helper holds performance as monado-xreal ($1 run)" \
    || fail "helper holds performance as monado-xreal ($1 run)"
  sleep 0.5
  kill -0 "$helper" 2>/dev/null \
    && pass "helper keeps the hold until stopped ($1 run)" \
    || fail "helper keeps the hold until stopped ($1 run)"
  [[ $(grep -c '^release' "$LOG") == 0 ]] \
    && pass "nothing is released before $1" || fail "nothing is released before $1"
  kill "-$1" "$helper"
  wait_bounded "$helper"
  wait "$helper" || status=$?
  assert_equals "helper exits 0 on $1" "$status" "0"
  wait_for_line 'release 7' \
    && pass "helper releases the hold's cookie on $1" \
    || fail "helper releases the hold's cookie on $1"
  assert_output_contains "helper logs the release" "$(cat "$SCRATCH/hold.err")" "released 'performance'"
}
held_then_stopped TERM
held_then_stopped INT

# A stop signal that lands while the hold is being taken is not lost.
: >"$LOG"
python3 -I "$HOLD" 2>/dev/null &
helper=$!
wait_for_exec "$helper" || fail "helper starts"
kill -TERM "$helper"
status=0
wait_bounded "$helper"
wait "$helper" || status=$?
[[ $status == 0 || $status == 143 ]] \
  && pass "an early SIGTERM still ends the helper cleanly" \
  || fail "an early SIGTERM still ends the helper cleanly (status $status)"
if grep -q '^hold' "$LOG" && ! grep -qx 'release 7' "$LOG"; then
  fail "a hold taken around an early SIGTERM is released"
else
  pass "a hold taken around an early SIGTERM is released"
fi

# Fail open: a refused hold, and no daemon on the bus at all.
: >"$LOG.refuse"
status=0
out=$(timeout 20 python3 -I "$HOLD" 2>&1) || status=$?
rm -f "$LOG.refuse"
assert_equals "helper exits 0 when the hold is refused" "$status" "0"
assert_output_contains "helper logs the refusal" "$out" "AccessDenied: refused"

status=0
out=$(DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SCRATCH/no-such-bus" \
  timeout 20 python3 -I "$HOLD" 2>&1) || status=$?
assert_equals "helper exits 0 with no system bus" "$status" "0"
assert_output_contains "helper logs why it is not holding" "$out" "not holding"

echo "# all monado-xreal performance-hold tests passed"
