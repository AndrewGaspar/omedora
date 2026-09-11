#!/bin/bash
#
# On Fedora, omarchy-system-lock reads the shell's answer to the lock request
# instead of discarding it (GitHub AndrewGaspar/omedora#9): a refused lock
# (missing-pam when /etc/pam.d/omarchy-lock-password is absent, failed, or an
# unreachable shell) is surfaced with a notification and a non-zero exit, and
# the lock-time side effects -- keyboard layout reset, 1password vault lock,
# screensaver shutdown -- do not run against a desktop that is still unlocked.
# The Arch branch keeps upstream's behavior byte for byte; system-lock-test.sh
# covers it on an Arch host, and the last case here pins it under an explicit
# OMARCHY_DISTRO=arch.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

system_lock="$ROOT/bin/omarchy-system-lock"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
notify_log="$tmpdir/notifications"
mkdir -p "$mock_bin"

# The Arch arm must still hold upstream's line verbatim (byte-identity relies
# on exactly this relocation).
grep -Fxq '  omarchy-shell lock lock >/dev/null' "$system_lock" ||
  fail "the Arch arm keeps the upstream lock call verbatim"
pass "the Arch arm keeps the upstream lock call verbatim"

for command in hyprctl pkill pidwait timeout omarchy-cmd-present; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done

# The shell answers the lock request with the IPC string under test, or is not
# running at all (omarchy-shell then reports that on stderr and exits 1).
cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
if [[ -n ${STUB_SHELL_DOWN:-} ]]; then
  echo "omarchy-shell is not running" >&2
  exit 1
fi
printf '%s\n' "$STUB_LOCK_RESULT"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
SH

# 1password is running (pgrep 0) unless a case says otherwise, so the vault
# lock step is reachable and its absence on a refused lock is meaningful.
cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit "${STUB_PGREP_STATUS:-0}"
SH
chmod +x "$mock_bin"/*

rc=0
run_lock() {
  local distro="$1" result="$2"

  : >"$call_log"
  : >"$notify_log"
  set +e
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" NOTIFY_LOG="$notify_log" \
    OMARCHY_DISTRO="$distro" STUB_LOCK_RESULT="$result" \
    STUB_SHELL_DOWN="${STUB_SHELL_DOWN:-}" STUB_PGREP_STATUS="${STUB_PGREP_STATUS:-0}" \
    XDG_RUNTIME_DIR="$tmpdir" \
    "$system_lock" >"$tmpdir/out" 2>"$tmpdir/err"
  rc=$?
  set -e
}

# The 1password step runs in a detached subshell, so give it a moment to log.
wait_for_call() {
  local pattern="$1" attempt

  for attempt in $(seq 1 50); do
    grep -q "$pattern" "$call_log" && return 0
    sleep 0.1
  done

  return 1
}

assert_lock_steps_ran() {
  local label="$1"
  local -a shutdown

  mapfile -t shutdown < <(grep -E '^(pkill|timeout) ' "$call_log" | grep -v 1password)
  [[ ${shutdown[0]:-} == "pkill -x ttfx" ]] ||
    fail "$label: stops ttfx before closing its terminal" "calls: $(cat "$call_log")"
  [[ ${shutdown[1]:-} == "timeout 1s pidwait -x ttfx" ]] ||
    fail "$label: waits for ttfx to exit" "calls: $(cat "$call_log")"
  [[ ${shutdown[2]:-} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
    fail "$label: closes the screensaver terminal after ttfx exits" "calls: $(cat "$call_log")"
  grep -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
    fail "$label: resets the keyboard layout" "calls: $(cat "$call_log")"
  wait_for_call '^timeout --kill-after=1s 3s 1password --lock$' ||
    fail "$label: locks the 1password vault" "calls: $(cat "$call_log")"
  pass "$label: runs the lock-time steps in upstream order"
}

assert_lock_steps_skipped() {
  local label="$1"

  [[ $(grep -c '^omarchy-shell lock lock$' "$call_log") == 1 ]] ||
    fail "$label: asks the shell to lock exactly once" "calls: $(cat "$call_log")"
  [[ $(grep -vc '^omarchy-shell ' "$call_log") == 0 ]] ||
    fail "$label: runs no lock-time step (layout, 1password, screensaver) on a refused lock" "calls: $(cat "$call_log")"
  pass "$label: leaves the still-unlocked desktop alone"
}

# --- Fedora, the shell locked -------------------------------------------------
run_lock fedora ok
(( rc == 0 )) || fail "fedora/ok: exits 0" "rc=$rc; stderr: $(cat "$tmpdir/err")"
[[ ! -s $notify_log ]] || fail "fedora/ok: sends no notification" "$(cat "$notify_log")"
pass "fedora/ok: exits 0 without a notification"
assert_lock_steps_ran "fedora/ok"

# --- Fedora, PAM service missing ---------------------------------------------
run_lock fedora missing-pam
(( rc != 0 )) || fail "fedora/missing-pam: exits non-zero"
pass "fedora/missing-pam: exits non-zero"
grep -q 'Lock screen unavailable' "$notify_log" ||
  fail "fedora/missing-pam: notifies that the lock screen is unavailable" "$(cat "$notify_log")"
grep -q 'PAM config missing' "$notify_log" ||
  fail "fedora/missing-pam: the notification names the missing PAM config" "$(cat "$notify_log")"
grep -q 'omarchy-apply-lock' "$notify_log" ||
  fail "fedora/missing-pam: the notification points at omarchy-apply-lock" "$(cat "$notify_log")"
grep -q -- '--exec omarchy-launch-floating-terminal-with-presentation omarchy-apply-lock' "$notify_log" ||
  fail "fedora/missing-pam: a click on the notification runs the repair in a terminal" "$(cat "$notify_log")"
[[ $(wc -l <"$notify_log") == 1 ]] || fail "fedora/missing-pam: sends exactly one notification" "$(cat "$notify_log")"
grep -q 'omarchy-apply-lock' "$tmpdir/err" ||
  fail "fedora/missing-pam: a terminal caller sees the repair command on stderr" "$(cat "$tmpdir/err")"
pass "fedora/missing-pam: notifies with the repair command"
assert_lock_steps_skipped "fedora/missing-pam"

# --- Fedora, any other refusal -------------------------------------------------
run_lock fedora failed
(( rc != 0 )) || fail "fedora/failed: exits non-zero"
grep -q 'Lock screen unavailable' "$notify_log" ||
  fail "fedora/failed: notifies that the lock screen is unavailable" "$(cat "$notify_log")"
grep -q 'failed' "$notify_log" ||
  fail "fedora/failed: the notification carries the shell's answer" "$(cat "$notify_log")"
grep -q 'PAM config missing' "$notify_log" &&
  fail "fedora/failed: a generic refusal is not reported as a missing PAM config" "$(cat "$notify_log")"
pass "fedora/failed: exits non-zero with a generic notification"
assert_lock_steps_skipped "fedora/failed"

# --- Fedora, shell not running ---------------------------------------------------
STUB_SHELL_DOWN=1 run_lock fedora ok
(( rc != 0 )) || fail "fedora/shell-down: exits non-zero"
grep -q 'not running' "$tmpdir/err" ||
  fail "fedora/shell-down: omarchy-shell's own explanation reaches stderr" "$(cat "$tmpdir/err")"
[[ ! -s $notify_log ]] ||
  fail "fedora/shell-down: sends no notification when the shell (the notification daemon) is down" "$(cat "$notify_log")"
pass "fedora/shell-down: exits non-zero after omarchy-shell's own error"
assert_lock_steps_skipped "fedora/shell-down"

# --- Arch: upstream behavior, unchanged -----------------------------------------
run_lock arch missing-pam
(( rc == 0 )) || fail "arch/missing-pam: still exits 0 as upstream does" "rc=$rc; stderr: $(cat "$tmpdir/err")"
[[ ! -s $notify_log ]] || fail "arch/missing-pam: upstream sends no notification" "$(cat "$notify_log")"
[[ ! -s $tmpdir/err ]] || fail "arch/missing-pam: upstream prints nothing" "$(cat "$tmpdir/err")"
pass "arch/missing-pam: the Arch branch is upstream's (answer discarded, exit 0)"
assert_lock_steps_ran "arch/missing-pam"
