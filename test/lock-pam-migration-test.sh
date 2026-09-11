#!/bin/bash
#
# L1: migrations/1788918004.sh restores /etc/pam.d/omarchy-lock-password on a
# Fedora install that lost it (GitHub AndrewGaspar/omedora#9). Without that
# service the Quickshell lock screen answers missing-pam and System > Lock does
# nothing. The migration must:
#   - exit 0 on Arch before calling anything (the inverse of the usual gate);
#   - exit 0 on Fedora without any privileged call when the file is present;
#   - call omarchy-apply-lock (which dispatches to bin/fedora/setup-lock) on
#     Fedora only when the file is absent.
#
# The migration repairs an absolute path no unprivileged suite can write, and
# an environment override in the shipped file would let a caller pick the file
# a root helper is asked to write. Like security-fido2-migration-test.sh, this
# test retargets a scratch copy instead and fails if the path is not named
# exactly once, so the seam cannot quietly stop standing for the shipped file.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
cd "$ROOT"

migration="$ROOT/migrations/1788918004.sh"
[[ -f $migration ]] || fail "migration exists: $migration"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

stub_bin="$TMP/bin"
calls="$TMP/calls.log"
pam_dir="$TMP/etc-pam.d"
pam_service="$pam_dir/omarchy-lock-password"
migration_copy="$TMP/migration.sh"
mkdir -p "$stub_bin" "$pam_dir"

# --- static contract ---------------------------------------------------------
mode=$(stat -c %a "$migration")
assert_equals "migration is mode 0644 (run via bash, not the executable bit)" "$mode" "644"
if head -n1 "$migration" | grep -q '^#!'; then
  fail "migration has no shebang line"
fi
pass "migration has no shebang line"
head -n1 "$migration" | grep -q '^echo "' || fail "migration starts with a one-line description echo"
pass "migration starts with a one-line description echo"

occurrences=$(grep -Fo /etc/pam.d/omarchy-lock-password "$migration" | wc -l) || occurrences=0
(( occurrences == 1 )) ||
  fail "the migration names the PAM service exactly once, so the test can retarget a copy (found $occurrences)"
grep -Fxq 'pam_service="/etc/pam.d/omarchy-lock-password"' "$migration" ||
  fail "the PAM service path is a fixed literal, not caller-controlled"
pass "migration names the PAM service once, and the test drives a retargeted copy"

if grep -vE '^[[:space:]]*#' "$migration" | grep -Eq '(^|[^[:alnum:]_-])sudo([^[:alnum:]_-]|$)'; then
  fail "the migration escalates only through omarchy-apply-lock, never with its own sudo"
fi
pass "the migration escalates only through omarchy-apply-lock"

sed "s|/etc/pam.d/omarchy-lock-password|$pam_service|" "$migration" >"$migration_copy"
if grep -Fq /etc/pam.d/ "$migration_copy"; then
  fail "the scratch copy redirects every live PAM path"
fi

# --- PATH stubs that log exact argv ------------------------------------------
cat >"$stub_bin/omarchy-distro" <<'SH'
#!/bin/bash
printf 'omarchy-distro %s\n' "$*" >>"$TEST_CALLS"
printf '%s\n' "$STUB_DISTRO"
SH
cat >"$stub_bin/omarchy-apply-lock" <<'SH'
#!/bin/bash
printf 'omarchy-apply-lock %s\n' "$*" >>"$TEST_CALLS"
exit "${STUB_APPLY_LOCK_STATUS:-0}"
SH
# The migration must decide before any escalation; a sudo here is a failure.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_CALLS"
exit 1
SH
chmod +x "$stub_bin"/*

run_migration() {
  local distro="$1"
  local rc

  : >"$calls"
  set +e
  ( export PATH="$stub_bin:$PATH" TEST_CALLS="$calls" STUB_DISTRO="$distro" \
      STUB_APPLY_LOCK_STATUS="${STUB_APPLY_LOCK_STATUS:-0}" HOME="$TMP/home"
    mkdir -p "$HOME"
    bash -euo pipefail "$migration_copy" ) >"$TMP/out" 2>&1
  rc=$?
  set -e
  return "$rc"
}

calls_matching() {
  grep -c "^$1" "$calls" || true
}

# --- Arch: the gate exits before calling anything ----------------------------
rm -f "$pam_service"
run_migration arch || fail "Arch run exits 0 (rc=$?)"
assert_equals "Arch run consults the distro once" "$(calls_matching omarchy-distro)" "1"
assert_equals "Arch run never calls omarchy-apply-lock" "$(calls_matching omarchy-apply-lock)" "0"
assert_equals "Arch run never escalates" "$(calls_matching sudo)" "0"
assert_output_contains "Arch run still prints its description" "$(cat "$TMP/out")" "Restore the lock screen PAM service"

# --- Fedora, service present: idempotent no-op, no sudo prompt ---------------
printf '#%%PAM-1.0\nauth include system-auth\n' >"$pam_service"
run_migration fedora || fail "Fedora run with the service present exits 0 (rc=$?)"
assert_equals "Fedora run with the service present never calls omarchy-apply-lock" "$(calls_matching omarchy-apply-lock)" "0"
assert_equals "Fedora run with the service present never escalates" "$(calls_matching sudo)" "0"
assert_equals "Fedora run leaves an existing service untouched" "$(cat "$pam_service")" $'#%PAM-1.0\nauth include system-auth'

# An administrator's own object at the path, even a dangling symlink, is not
# ours to replace: apply-lock would write through the link.
rm -f "$pam_service"
ln -s "$TMP/nowhere" "$pam_service"
run_migration fedora || fail "Fedora run with a dangling symlink exits 0 (rc=$?)"
assert_equals "Fedora run leaves a dangling symlink at the path alone" "$(calls_matching omarchy-apply-lock)" "0"
rm -f "$pam_service"

# --- Fedora, service absent: repaired through omarchy-apply-lock -------------
run_migration fedora || fail "Fedora run with the service absent exits 0 (rc=$?)"
assert_equals "Fedora run with the service absent calls omarchy-apply-lock once" "$(calls_matching omarchy-apply-lock)" "1"
assert_equals "omarchy-apply-lock is called with no arguments" "$(grep '^omarchy-apply-lock' "$calls")" "omarchy-apply-lock "
assert_equals "the migration itself never escalates (apply-lock owns sudo)" "$(calls_matching sudo)" "0"

# A failed repair must stay pending: omarchy-migrate writes the completion
# marker only after exit 0, so the migration may not swallow the failure.
if STUB_APPLY_LOCK_STATUS=1 run_migration fedora; then
  fail "a failing omarchy-apply-lock leaves the migration pending (non-zero exit)"
fi
pass "a failing omarchy-apply-lock leaves the migration pending (non-zero exit)"

echo "# all lock-pam-migration tests passed"
